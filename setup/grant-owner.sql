-- Создайте пользователя вручную в Authentication → Users.
-- Замените ВАШ_EMAIL на его email. Запрос не создаёт аккаунт и не меняет пароль.
insert into public.site_admins(user_id)
select id from auth.users where lower(email)=lower('ВАШ_EMAIL')
on conflict(user_id) do nothing;

-- Проверка результата: должна появиться одна строка для выбранного аккаунта.
select a.user_id,u.email from public.site_admins a
join auth.users u on u.id=a.user_id
where lower(u.email)=lower('ВАШ_EMAIL');
