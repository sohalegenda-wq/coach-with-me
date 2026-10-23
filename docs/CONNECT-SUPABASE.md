# Подключение Supabase: инструкция для первого запуска

Нужно настроить три части: база в Supabase, переменные сборки в Cloudflare и серверные Edge Functions. Публичный ключ сам по себе не создаёт таблицы.

## 1. Откройте проект

1. Откройте https://supabase.com/dashboard и выберите свой проект.
2. В Project Settings → Data API найдите Project URL — адрес вида `https://YOUR_PROJECT.supabase.co`, без `/rest/v1/`.
3. В Project Settings → API Keys найдите Publishable key (начинается с `sb_publishable_`) или legacy anon key. Это публичный ключ сайта. Не используйте secret/service_role key.

## 2. Создайте базу через SQL Editor

Если вы ещё не выполняли миграции CWM:

1. В GitHub откройте `supabase/setup-sql-editor.sql`.
2. Нажмите Raw. Скопируйте весь текст (Ctrl+A, Ctrl+C).
3. Вернитесь в Supabase. Слева выберите SQL Editor → New query.
4. Вставьте текст и нажмите Run.
5. В результате должны быть три столбца: `courses = 5`, `lessons = 19`, `exam_questions = 115`.

Файл создаёт таблицы, RLS, проверку заданий/экзаменов и стартовые материалы одной транзакцией. Запускайте его один раз. Если исходные миграции уже выполнены, этот файл запускать не нужно. При ошибке `already exists` не удаляйте таблицы: сохраните полный текст ошибки для разбора. Не отключайте RLS.

Если существует старая `profiles` со столбцами `id`, `username`, `display_name`, `license`, `created_at`, используйте [отдельное продолжение установки](LEGACY-PROFILES.md). Для такой базы обычный файл установки не подходит.

Повторная проверка содержимого (без изменения базы):

```sql
select
  (select count(*) from public.courses) as courses,
  (select count(*) from public.lessons) as lessons,
  (select count(*) from public.exam_questions) as exam_questions;
```

`setup-sql-editor.sql` — объединённая копия двух файлов в `supabase/migrations/`, а не третья миграция. Вносите изменения в исходные миграции только до первого развёртывания, затем пересоздайте файл командой `npm run db:bundle`. Для обновлений работающей базы нужны новые миграции.

## 3. Подключите Cloudflare

1. В Cloudflare откройте Workers & Pages → ваш проект → Settings → настройки сборки.
2. Найдите Variables and Secrets / Build variables. У Workers нужны переменные именно **Build**, а не только переменные запуска Worker: Vite читает их при сборке.
3. Добавьте:

| Имя | Значение |
| --- | --- |
| `VITE_SUPABASE_URL` | Корневой Project URL |
| `VITE_SUPABASE_ANON_KEY` | Publishable key или legacy anon key |

4. Сохраните и запустите новую production-сборку последнего коммита `main`.

Изменение переменных без пересборки не меняет уже опубликованный JS. Для Pages переменные задаются для Production (при необходимости отдельно Preview). Не размещайте в Cloudflare ключ ИИ и service_role.

## 4. Настройте регистрацию и письма

1. В Supabase откройте Authentication → Sign In / Providers и включите Email.
2. Включите регистрацию и подтверждение email, минимум пароля — 10 символов.
3. Authentication → URL Configuration:
   - Site URL: полный адрес вашего опубликованного сайта (например `https://YOUR_SITE.workers.dev` или `https://YOUR_SITE.pages.dev`).
   - Redirect URLs: добавьте этот же адрес и этот адрес с `/**` в конце.
4. Сохраните.
5. Для доставки писем обычным пользователям подключите SMTP в настройках Email/SMTP. Можно использовать поставщика с бесплатной квотой. Встроенная тестовая почта Supabase ограничена по получателям и частоте; она не обеспечивает публичную регистрацию всех пользователей.

Ссылку подтверждения/восстановления открывайте в том же браузере, где отправляли запрос. После подтверждения можно входить на другом устройстве обычным email/паролем.

## 5. Разверните две Edge Functions

SQL Editor создаёт базу, но не публикует Edge Functions. Без них регистрация и чтение могут работать, однако сохранение профиля, проверка уроков, экзамены и админ-действия не будут работать полностью.

На компьютере установите Node.js 22.12+ с https://nodejs.org/. Затем:

1. В GitHub → Code → Download ZIP скачайте исходники.
2. Распакуйте архив.
3. Откройте терминал в папке, где находятся `package.json` и `supabase/`.
4. Выполните:

```bash
npx --yes supabase@2.121.0 login
npx --yes supabase@2.121.0 functions deploy academy-api --project-ref YOUR_PROJECT_REF
npx --yes supabase@2.121.0 functions deploy coach --project-ref YOUR_PROJECT_REF
```

`YOUR_PROJECT_REF` — часть адреса между `https://` и `.supabase.co`. Войдите в CLI через предложенный им процесс. Не отправляйте токены и пароль БД в чат. Для этих команд не нужен `db push`: SQL уже применён через Editor.

После успешного deploy в Supabase → Edge Functions должны появиться `academy-api` и `coach`. Файл `supabase/config.toml` отключает только legacy-проверку JWT на шлюзе; обе функции самостоятельно проверяют пользовательский токен через Auth.

## 6. Разрешите домен сайта для функций

В Supabase → Edge Functions → Secrets добавьте:

| Имя | Значение |
| --- | --- |
| `ALLOWED_ORIGINS` | Полный origin сайта, например `https://YOUR_SITE.workers.dev`, без `/` в конце |
| `AI_PROVIDER` | `disabled` |

Несколько origins перечисляются через запятую. API-ключ ИИ сейчас не нужен. Учебный наставник работает без него; включение ИИ описано отдельно в SUPABASE.md.

## 7. Проверьте и назначьте администратора

1. На сайте создайте аккаунт и подтвердите email.
2. Сохраните черновик первого урока. Войдите в другом браузере: должен открыться тот же прогресс.
3. В Supabase → Authentication → Users найдите свой UUID.
4. Выполните в SQL Editor, подставив UUID:

```sql
update public.app_roles
set role = 'admin'
where user_id = 'YOUR_USER_UUID'::uuid
returning user_id, role;
```

5. Выйдите из аккаунта и войдите снова. Появится «Администратор».

Лицензии выдаются после официального экзамена и ручной проверки трёх письменных задач. Администратор не может проверять свою работу: для этого нужен другой администратор.

При ошибке сохраните её точный текст и укажите, на каком шаге она возникла. Не присылайте секретные ключи.
