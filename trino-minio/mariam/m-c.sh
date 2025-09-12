#!/bin/bash

# Проверить все параметры связанные с соединениями
docker exec maria mariadb -u root -padmin -e "SHOW GLOBAL STATUS LIKE '%conn%'"

# Проверить настройки таймаутов
docker exec maria mariadb -u root -padmin -e "SHOW VARIABLES LIKE '%timeout%'"

# Посмотреть текущие процессы
docker exec maria mariadb -u root -padmin -e "SHOW PROCESSLIST"

# Проверить максимальное количество соединений
docker exec maria mariadb -u root -padmin -e "SHOW VARIABLES LIKE 'max_connections'"