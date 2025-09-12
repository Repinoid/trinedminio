# Используем официальный образ MariaDB


FROM mariadb:latest

# Устанавливаем ping для диагностики
RUN apt-get update && \
    apt-get install -y iputils-ping && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Копируем оптимизированный конфиг
# COPY ./maria.cnf /etc/mysql/conf.d/

# Сохраняем оригинальную точку входа MariaDB

# docker build -t mariamping -f mariadb.ping.dockerfile .
