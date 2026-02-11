FROM nginx:alpine

COPY . /usr/share/nginx/html

RUN printf '%s\n' \
	'server {' \
	'  listen 80;' \
	'  server_name _;' \
	'  root /usr/share/nginx/html;' \
	'' \
	'  charset utf-8;' \
	'' \
	'  add_header X-Content-Type-Options nosniff always;' \
	'' \
	'  # Force a correct MIME type for WebAssembly even in minimal/misconfigured environments.' \
	'  location ~* \\.wasm$ {' \
	'    default_type application/wasm;' \
	'    try_files $uri =404;' \
	'  }' \
	'' \
	'  location / {' \
	'    try_files $uri $uri/ =404;' \
	'  }' \
	'}' \
	> /etc/nginx/conf.d/default.conf
