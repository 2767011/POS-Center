# Web server 192.168.20.229

Снимок и памятка по веб-серверу `pee-bo-sr-web1`.

## Доступ

- SSH: `ssh root@192.168.20.229`
- SSH user: `root`
- SSH password: см. `.secrets.local.md` (рядом, в .gitignore)
- Public page: `http://192.168.20.229/`
- Admin page: `http://192.168.20.229/admin`
- Admin direct script: `http://192.168.20.229/admin.php`
- Admin password: см. `.secrets.local.md` (рядом, в .gitignore)

## Что крутится

- OS/web host: Debian, Apache `2.4.66`
- Apache vhost: `/etc/apache2/sites-available/files.conf`
- Enabled vhost: `/etc/apache2/sites-enabled/files.conf`
- DocumentRoot: `/var/www/files`
- Admin PHP file: `/var/www/files/admin.php`
- Admin password hash: `/var/www/files/.admin_password`
- Settings file: `/var/www/files/.settings.json`

## Изменение от 2026-05-15

Добавлен короткий URL админки без расширения:

```apache
Alias /admin /var/www/files/admin.php
```

После изменения выполнено:

```bash
apache2ctl configtest
systemctl reload apache2
```

Проверено: `http://192.168.20.229/admin` возвращает страницу входа файлового менеджера.

Бэкап конфига на сервере:

```text
/etc/apache2/sites-available/files.conf.bak.20260515152726
```

## Локальные копии в проекте

- `apache/files.conf` - текущий Apache vhost.
- `www-files/admin.php` - PHP-файловый менеджер.
- `www-files/admin_password.hash` - bcrypt-хэш пароля админки.
- `www-files/settings.json` - локальная копия настроек, если файл был на сервере.
- `server_listing.txt` - hostname, Apache vhost dump и список `/var/www/files`.

## Восстановление короткого URL

Если настройка потеряется, добавить в `<VirtualHost *:80>` сразу после `DocumentRoot /var/www/files`:

```apache
Alias /admin /var/www/files/admin.php
```

Затем проверить и перезагрузить Apache:

```bash
apache2ctl configtest
systemctl reload apache2
```
