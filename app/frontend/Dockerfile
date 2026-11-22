# frontend kontejner: staticki UI na nginx-u.
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY tetris.html /usr/share/nginx/html/tetris.html
EXPOSE 80
