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
	'  # This project reuses the same tag during iteration (e.g. v0.1.0), so avoid sticky browser caches.' \
	'  # Otherwise users may keep running an older .pck/.wasm and think fixes did not apply.' \
	'  location = /index.html {' \
	'    add_header Cache-Control "no-store" always;' \
	'    try_files $uri =404;' \
	'  }' \
	'' \
	'  location ~* \\.(pck|wasm|js|data)$ {' \
	'    add_header Cache-Control "no-cache" always;' \
	'    try_files $uri =404;' \
	'  }' \
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
