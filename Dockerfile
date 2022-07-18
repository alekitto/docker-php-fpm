ARG PHP_VERSION=8.1.8
ARG LIBMAXMINDDB_VERSION=1.6.0
ARG LIBXML2_VERSION=2.9.14
ARG LIBWEBP_VERSION=1.2.2

FROM bitnami/minideb:bullseye as libmaxminddb_build

ARG LIBMAXMINDDB_VERSION

RUN mkdir -p /bitnami/blacksmith-sandbox
RUN install_packages ca-certificates curl git build-essential

WORKDIR /bitnami/blacksmith-sandbox

RUN curl -sSL -olibmaxminddb.tar.gz https://github.com/maxmind/libmaxminddb/releases/download/${LIBMAXMINDDB_VERSION}/libmaxminddb-${LIBMAXMINDDB_VERSION}.tar.gz && \
    tar xf libmaxminddb.tar.gz

RUN cd libmaxminddb-${LIBMAXMINDDB_VERSION} && \
    ./configure --prefix=/opt/bitnami/common && \
    make -j4 && \
    make install

FROM bitnami/minideb:bullseye as imap_build

RUN mkdir -p /opt/blacksmith-sandbox
RUN install_packages ca-certificates curl git build-essential unzip libpam0g-dev libssl-dev libkrb5-dev

WORKDIR /bitnami/blacksmith-sandbox

RUN curl -sSL -oimap.zip https://github.com/uw-imap/imap/archive/refs/heads/master.zip && \
    unzip imap.zip && \
    mv imap-master imap-2007.0.0

RUN cd imap-2007.0.0 && \
    touch ip6 && \
    make ldb IP=6 SSLTYPE=unix.nopwd EXTRACFLAGS=-fPIC

FROM bitnami/minideb:bullseye as php_build

ARG PHP_VERSION

RUN mkdir -p /opt/blacksmith-sandbox
RUN install_packages ca-certificates curl git build-essential unzip libssl-dev

WORKDIR /bitnami/blacksmith-sandbox

RUN curl -sSL -ophp.tar.gz https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz && \
    tar xf php.tar.gz

RUN install_packages libkrb5-dev

COPY --from=imap_build /bitnami/blacksmith-sandbox/imap-2007.0.0 /bitnami/blacksmith-sandbox/imap-2007.0.0
RUN install_packages pkg-config build-essential autoconf bison re2c

RUN cd /bitnami/blacksmith-sandbox/php-${PHP_VERSION} && \
    ./buildconf -f

RUN install_packages libtool automake

ARG LIBXML2_VERSION
RUN curl -sSL -olibxml.tar.gz https://gitlab.gnome.org/GNOME/libxml2/-/archive/v${LIBXML2_VERSION}/libxml2-v${LIBXML2_VERSION}.tar.gz && \
    tar xf libxml.tar.gz && \
    cd libxml2-v${LIBXML2_VERSION} && \
    ./autogen.sh && ./configure && make -j4 && make install

RUN curl -sSL -osqlite3.tar.gz https://www.sqlite.org/2022/sqlite-autoconf-3390000.tar.gz && \
    tar xf sqlite3.tar.gz && \
    cd sqlite-autoconf-3390000 && \
    ./configure && make -j4 && make install

RUN install_packages zlib1g-dev libbz2-dev libcurl4-openssl-dev libpng-dev

ARG LIBWEBP_VERSION
RUN install_packages unzip
RUN curl -sSL -olibwebp.zip https://github.com/webmproject/libwebp/archive/refs/tags/v${LIBWEBP_VERSION}.zip && \
    unzip libwebp.zip && \
    cd libwebp-${LIBWEBP_VERSION} && \
    ./autogen.sh && \
    ./configure && make -j4 && make install

RUN install_packages libjpeg-dev libfreetype6-dev libgmp-dev libpam0g-dev libicu-dev libldap2-dev libonig-dev freetds-dev
RUN install_packages gnupg && \
    (curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null) && \
    echo "deb http://apt.postgresql.org/pub/repos/apt bullseye-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    install_packages libpq-dev

RUN install_packages libreadline-dev libsodium-dev libtidy-dev libxslt1-dev libzip-dev

ENV EXTENSION_DIR=/opt/bitnami/php/lib/php/extensions
RUN /bitnami/blacksmith-sandbox/php-${PHP_VERSION}/configure --prefix=/opt/bitnami/php --with-imap=/bitnami/blacksmith-sandbox/imap-2007.0.0 --with-imap-ssl --with-zlib --with-libxml-dir=/usr --enable-soap --disable-rpath --enable-inline-optimization --with-bz2 \
    --enable-sockets --enable-pcntl --enable-exif --enable-bcmath --with-pdo-mysql=mysqlnd --with-mysqli=mysqlnd --with-png-dir=/usr --with-openssl --with-libdir=/lib/$(gcc -dumpmachine) --enable-ftp --enable-calendar --with-gettext --with-xmlrpc --with-xsl --enable-fpm \
    --with-fpm-user=daemon --with-fpm-group=daemon --enable-mbstring --enable-cgi --enable-ctype --enable-session --enable-mysqlnd --enable-intl --with-iconv --with-pdo_sqlite --with-sqlite3 --with-readline --with-gmp --with-curl --with-pdo-pgsql=shared \
    --with-pgsql=shared --with-config-file-scan-dir=/opt/bitnami/php/etc/conf.d --enable-simplexml --with-sodium --enable-gd --with-pear --with-freetype --with-jpeg --with-webp --with-zip --with-pdo-dblib=shared --with-tidy --with-ldap=/usr/ --enable-apcu=shared --enable-opcache
RUN make -j4
RUN make install

ENV PATH=/opt/bitnami/php/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/bitnami/lib

RUN mkdir -p /opt/bitnami/lib && \ 
    cp /usr/local/lib/*.so* /opt/bitnami/lib/.

RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
    php composer-setup.php --install-dir=/opt/bitnami/php/bin --filename=composer

RUN mkdir -p /opt/bitnami/php/logs && \
    mkdir -p /opt/bitnami/php/tmp && \
    mkdir -p /opt/bitnami/php/var/{log,run}

COPY --from=libmaxminddb_build /opt/bitnami/common /opt/bitnami/common
COPY common.conf /opt/bitnami/php/etc/.
COPY environment.conf /opt/bitnami/php/etc/.
COPY php-fpm.conf /opt/bitnami/php/etc/.
COPY php.ini /opt/bitnami/php/etc/.
COPY php.ini-development /opt/bitnami/php/etc/.
COPY php.ini-production /opt/bitnami/php/etc/.
COPY www.conf /opt/bitnami/php/etc/php-fpm.d/.

RUN find /opt/bitnami/ -name "*.so*" -type f | xargs strip --strip-debug
RUN find /opt/bitnami/ -executable -type f | xargs strip --strip-unneeded || true
RUN mkdir -p /opt/bitnami/php/etc/conf.d

RUN php -i # Test run executable

FROM bitnami/minideb:bullseye as php_intermediate

ARG DIRS_TO_TRIM="/usr/share/man \
/var/cache/apt \
/var/lib/apt/lists \
/usr/share/locale \
/var/log \
/usr/share/info \
"

ENV BITNAMI_APP_NAME=php-fpm \
    BITNAMI_IMAGE_VERSION="${PHP_VERSION}-prod-debian-10" \
    PATH="/opt/bitnami/php/bin:/opt/bitnami/php/sbin:$PATH" \
    LD_LIBRARY_PATH=/opt/bitnami/lib \
    OS_ARCH="amd64" \
    OS_FLAVOUR="debian-10" \
    OS_NAME="linux"

RUN install_packages ca-certificates curl gzip libbsd0 libbz2-1.0 libc6 libcom-err2 libcurl4 libexpat1 libffi7 libfftw3-double3 libfontconfig1 libfreetype6 libgcc1 libgcrypt20 libglib2.0-0 libgmp10 libgnutls30 libgomp1 libgpg-error0 libgssapi-krb5-2 libhogweed6 libicu67 libidn2-0 libjpeg62-turbo libk5crypto3 libkeyutils1 libkrb5-3 libkrb5support0 liblcms2-2 libldap-2.4-2 liblqr-1-0 libltdl7 liblzma5 libmagickcore-6.q16-6 libmagickwand-6.q16-6 libmemcached11 libmemcachedutil2 libncurses6 libnettle8 libnghttp2-14 libonig5 libp11-kit0 libpcre3 libpng16-16 libpq5 libpsl5 libreadline8 librtmp1 libsasl2-2 libsodium23 libssh2-1 libssl1.1 libstdc++6 libsybdb5 libtasn1-6 libtidy5deb1 libtinfo6 libunistring2 libuuid1 libx11-6 libxau6 libxcb1 libxdmcp6 libxext6 libxslt1.1 libzip4 netselect-apt procps tar wget zlib1g && \
    mkdir -p /app && \
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS    90/' /etc/login.defs && \
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS    0/' /etc/login.defs && \
    sed -i 's/sha512/sha512 minlen=8/' /etc/pam.d/common-password && \
    for DIR in $DIRS_TO_TRIM; do \
      rm -rf "$DIR/*" ; \
    done && \
    rm /var/cache/ldconfig/aux-cache && \
    find /usr/share/doc -mindepth 2 -not -name copyright -not -type d -delete && \
    find /usr/share/doc -mindepth 1 -type d -empty -delete

EXPOSE 9000

COPY --from=php_build /opt/bitnami /opt/bitnami
WORKDIR /app

CMD ["php-fpm" "-F" "--pid" "/opt/bitnami/php/tmp/php-fpm.pid" "-y" "/opt/bitnami/php/etc/php-fpm.conf"]

