create or replace function public.guard_images() returns trigger
language plpgsql as $$
declare rc text; hosted boolean; base int; nimg int; nmap int;
begin
  if current_user not in ('anon', 'authenticated') then
    if tg_op = 'DELETE' then return old; end if; return new;
  end if;
  if tg_op = 'DELETE' then rc := old.room; else rc := new.room; end if;
  select host_hash is not null, case when map_path is null then 0 else 1 end into hosted, base from public.rooms where code = rc;
  if tg_op <> 'INSERT' and coalesce(old.data ->> 'k', '') = 'map' and coalesce(hosted, false) and not coalesce(public.is_host(rc), false) then
    raise exception 'Only the host can change maps';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if tg_op = 'UPDATE' and coalesce(new.data ->> 'k', '') is distinct from coalesce(old.data ->> 'k', '') then
    raise exception 'Not allowed';
  end if;
  if tg_op = 'INSERT' and exists (select 1 from public.marks where id = new.id) then return new; end if;
  if tg_op = 'INSERT' and new.data ->> 'type' = 'img' then
    if new.data ->> 'k' = 'map' and coalesce(hosted, false) and not coalesce(public.is_host(rc), false) then
      raise exception 'Only the host can change maps';
    end if;
    select count(*), count(*) filter (where data ->> 'k' = 'map') into nimg, nmap
      from public.marks where room = rc and data ->> 'type' = 'img';
    if new.data ->> 'k' = 'map' and nmap + coalesce(base, 0) >= 10 then raise exception 'Map limit reached (10)'; end if;
    if nimg + coalesce(base, 0) >= 50 then raise exception 'Image limit reached (50)'; end if;
  end if;
  return new;
end $$;

drop trigger if exists marks_images on public.marks;
create trigger marks_images before insert or update or delete on public.marks
  for each row execute function public.guard_images();
