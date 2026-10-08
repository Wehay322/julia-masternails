-- Выполните в Supabase SQL Editor. Аккаунт владельца создаётся вручную.
create table if not exists public.site_admins(user_id uuid primary key references auth.users(id) on delete cascade);
alter table public.site_admins enable row level security;
create policy admin_self_read on public.site_admins for select to authenticated using(user_id=auth.uid());
create or replace function public.is_site_admin() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.site_admins where user_id=auth.uid())$$;
revoke all on function public.is_site_admin() from public;
grant execute on function public.is_site_admin() to authenticated;
grant select on public.site_admins to authenticated;
revoke insert,update,delete on public.site_admins from anon,authenticated;

create table if not exists public.site_content(id integer primary key check(id=1),content jsonb not null,updated_at timestamptz not null default now());
alter table public.site_content enable row level security;
create policy public_content on public.site_content for select to anon,authenticated using(true);
create policy owner_content on public.site_content for all to authenticated using(public.is_site_admin()) with check(public.is_site_admin());
grant select on public.site_content to anon,authenticated;
grant insert,update,delete on public.site_content to authenticated;
create or replace function public.validate_site_content() returns trigger language plpgsql set search_path=public as $$
declare s jsonb;begin
 if jsonb_typeof(new.content) <> 'object' or coalesce(length(trim(new.content->>'brand')),0) not between 1 and 200 or coalesce(jsonb_typeof(new.content->'services'),'')<>'array' or coalesce(jsonb_typeof(new.content->'gallery'),'')<>'array' or new.content->'labels' is null or new.content->'hero' is null or new.content->'about' is null or new.content->'contacts' is null or new.content->'settings' is null then raise exception 'Проверьте структуру и название сайта';end if;
 for s in select * from jsonb_array_elements(new.content->'services') loop
  if coalesce(length(trim(s->>'id')),0)=0 or coalesce(length(trim(s->>'name')),0)=0 or coalesce(length(trim(s->>'price')),0)=0 then raise exception 'Заполните название, идентификатор и цену услуги';end if;
 end loop;
 if (new.content#>>'{settings,primary}') !~ '^#[0-9a-fA-F]{6}$' or (new.content#>>'{settings,background}') !~ '^#[0-9a-fA-F]{6}$' or (new.content#>>'{settings,card}') !~ '^#[0-9a-fA-F]{6}$' then raise exception 'Некорректный цвет';end if;
 new.updated_at=now();return new;end$$;
create trigger validate_content before insert or update on public.site_content for each row execute function public.validate_site_content();

create table if not exists public.bookings(id uuid primary key default gen_random_uuid(),service text not null,date date not null,time time not null,name text not null check(length(trim(name)) between 2 and 80),phone text not null check(length(phone) between 10 and 25),status text not null default 'new' check(status in('new','confirmed','completed','cancelled')),created_at timestamptz not null default now());
create unique index if not exists unique_active_slot on public.bookings(date,time) where status<>'cancelled';
alter table public.bookings enable row level security;
create policy owner_bookings on public.bookings for all to authenticated using(public.is_site_admin()) with check(public.is_site_admin());
revoke all on public.bookings from anon;
grant select,update,delete on public.bookings to authenticated;
create or replace function public.create_booking(p_service text,p_date date,p_time time,p_name text,p_phone text) returns uuid language plpgsql security definer set search_path=public as $$
declare new_id uuid;begin
 if length(trim(p_name)) not between 2 and 80 or length(p_phone) not between 10 and 25 or length(regexp_replace(p_phone,'\D','','g')) not between 10 and 15 then raise exception 'Проверьте имя и телефон';end if;
 if p_date< (now() at time zone 'Europe/Moscow')::date or p_date> (now() at time zone 'Europe/Moscow')::date+180 or ((p_date+p_time) at time zone 'Europe/Moscow')<=now() then raise exception 'Выберите будущую дату в ближайшие 180 дней';end if;
 if p_time not in('10:00'::time,'12:00'::time,'14:00'::time,'16:00'::time,'18:00'::time) then raise exception 'Выберите доступное время';end if;
 if not exists(select 1 from public.site_content,jsonb_array_elements(content->'services') s where id=1 and s->>'id'=p_service) then raise exception 'Услуга недоступна';end if;
 perform pg_advisory_xact_lock(hashtext(regexp_replace(p_phone,'\D','','g')));
 if (select count(*) from public.bookings where regexp_replace(phone,'\D','','g')=regexp_replace(p_phone,'\D','','g') and created_at>now()-interval '1 day')>=3 then raise exception 'Слишком много заявок. Свяжитесь с мастером';end if;
 insert into public.bookings(service,date,time,name,phone) values(p_service,p_date,p_time,trim(p_name),p_phone) returning id into new_id;return new_id;
 exception when unique_violation then raise exception 'Это время уже занято. Выберите другое';end$$;
revoke all on function public.create_booking(text,date,time,text,text) from public;
grant execute on function public.create_booking(text,date,time,text,text) to anon,authenticated;
create or replace function public.booked_times(p_date date) returns setof time language sql stable security definer set search_path=public as $$select time from public.bookings where date=p_date and status<>'cancelled'$$;
revoke all on function public.booked_times(date) from public;
grant execute on function public.booked_times(date) to anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('site-images','site-images',true,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy read_site_images on storage.objects for select to anon,authenticated using(bucket_id='site-images');
create policy owner_upload_images on storage.objects for insert to authenticated with check(bucket_id='site-images' and public.is_site_admin());
create policy owner_delete_images on storage.objects for delete to authenticated using(bucket_id='site-images' and public.is_site_admin());

-- После создания пользователя замените UUID и выполните:
-- insert into public.site_admins(user_id) values('UUID-ВАШЕГО-ПОЛЬЗОВАТЕЛЯ');
