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
	'  # Ensure correct MIME for WebAssembly in minimal environments.' \
	'  types { application/wasm wasm; }' \
	'' \
	'  add_header X-Content-Type-Options nosniff always;' \
	'' \
	'  location / {' \
	'    try_files $uri $uri/ =404;' \
	'  }' \
	'}' \
	> /etc/nginx/conf.d/default.conf
