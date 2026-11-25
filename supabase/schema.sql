-- ATHAR schema. Run in Supabase > SQL Editor.
create table categories(id serial primary key,name text not null,sort int default 0);
insert into categories(name,sort) values('تيشيرتات',1),('هوديز',2),('سويت شيرت',3),('جاكيتات',4),('بناطيل',5),('إكسسوارات',6),('أخرى',7);
create table collections(id serial primary key,number int,name text not null,description text,cover_url text,published_at date default current_date,visible bool default false,archived bool default false);
create table products(id uuid primary key default gen_random_uuid(),name text not null,description text,price int not null check(price>=0),
 category_id int references categories,collection_id int references collections on delete set null,images text[] default '{}',
 label text not null default 'regular' check(label in('single','limited','regular')),featured bool default false,published bool default false,sort int default 0,created_at timestamptz default now());
create table product_sizes(product_id uuid references products on delete cascade,size text,qty int not null default 0 check(qty>=0),primary key(product_id,size));
create table orders(id uuid primary key default gen_random_uuid(),number bigint generated always as identity,request_key text unique,
 name text not null,phone text not null,governorate text not null,district text not null,address text not null,notes text,delivery_fee int not null,total int not null,
 status text not null default 'new' check(status in('new','confirmed','preparing','shipped','completed','cancelled')),created_at timestamptz default now());
create table order_items(id serial primary key,order_id uuid references orders on delete cascade,product_id uuid references products on delete set null,product_name text,size text,qty int,price int);
create table admins(user_id uuid primary key references auth.users on delete cascade);

create function is_admin() returns bool language sql security definer stable set search_path=public as $$ select exists(select 1 from admins where user_id=auth.uid()) $$;

do $$ declare t text; begin
 foreach t in array array['categories','collections','products','product_sizes','orders','order_items','admins'] loop
  execute format('alter table %I enable row level security',t); end loop;
 foreach t in array array['categories','collections','products','product_sizes','orders','order_items'] loop
  execute format('create policy admin_all on %I for all using(is_admin()) with check(is_admin())',t); end loop;
end $$;
create policy pub_cat on categories for select using(true);
create policy pub_col on collections for select using(visible);
create policy pub_prod on products for select using(published);
create policy pub_size on product_sizes for select using(exists(select 1 from products p where p.id=product_id and p.published));
create policy self on admins for select using(user_id=auth.uid());

-- Atomic order placement: row locks prevent two buyers taking the last piece.
create function place_order(p jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare o orders; r record; pr products; sz product_sizes; q int; sub int:=0; fee int:=5000;
begin
 if length(coalesce(trim(p->>'name'),''))<2 or length(coalesce(trim(p->>'phone'),''))<7 or coalesce(trim(p->>'governorate'),'')=''
    or coalesce(trim(p->>'district'),'')='' or coalesce(trim(p->>'address'),'')='' or coalesce(p->>'key','')='' then raise exception 'يرجى إكمال بيانات التوصيل'; end if;
 select * into o from orders where request_key=p->>'key';
 if found then return jsonb_build_object('number',o.number,'total',o.total,'fee',o.delivery_fee); end if;
 if jsonb_typeof(p->'items')<>'array' or jsonb_array_length(p->'items')=0 then raise exception 'الحقيبة فارغة'; end if;
 insert into orders(request_key,name,phone,governorate,district,address,notes,delivery_fee,total)
  values(p->>'key',trim(p->>'name'),trim(p->>'phone'),trim(p->>'governorate'),trim(p->>'district'),trim(p->>'address'),nullif(trim(p->>'notes'),''),fee,0) returning * into o;
 for r in select v from jsonb_array_elements(p->'items') t(v) order by v->>'id',v->>'size' loop
  q:=(r.v->>'qty')::int; if q is null or q<1 then raise exception 'كمية غير صالحة'; end if;
  select * into pr from products where id=(r.v->>'id')::uuid and published;
  if not found then raise exception 'قطعة غير متوفرة'; end if;
  select * into sz from product_sizes where product_id=pr.id and size=r.v->>'size' for update;
  if not found or sz.qty<q then raise exception 'نفذت الكمية المطلوبة من: %',pr.name; end if;
  update product_sizes set qty=qty-q where product_id=pr.id and size=sz.size;
  insert into order_items(order_id,product_id,product_name,size,qty,price) values(o.id,pr.id,pr.name,sz.size,q,pr.price);
  sub:=sub+pr.price*q;
 end loop;
 update orders set total=sub+fee where id=o.id;
 return jsonb_build_object('number',o.number,'total',sub+fee,'fee',fee);
end $$;
grant execute on function place_order(jsonb) to anon,authenticated;

-- Restore stock on cancel; a cancelled order cannot be re-opened (would double-count stock).
create function orders_status_guard() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if old.status='cancelled' and new.status<>'cancelled' then raise exception 'لا يمكن إعادة فتح طلب ملغي'; end if;
 if new.status='cancelled' and old.status<>'cancelled' then
  update product_sizes s set qty=s.qty+i.qty from order_items i where i.order_id=new.id and s.product_id=i.product_id and s.size=i.size; end if;
 return new;
end $$;
create trigger orders_status before update of status on orders for each row execute function orders_status_guard();

-- Storage for product images
insert into storage.buckets(id,name,public) values('products','products',true);
create policy img_read on storage.objects for select using(bucket_id='products');
create policy img_admin on storage.objects for all using(bucket_id='products' and public.is_admin()) with check(bucket_id='products' and public.is_admin());

-- After creating your admin user in Authentication > Users, run:
-- insert into admins(user_id) select id from auth.users where email='YOUR_EMAIL';
