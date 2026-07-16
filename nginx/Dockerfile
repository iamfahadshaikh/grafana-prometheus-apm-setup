FROM nginx:1.28-alpine

RUN apk add --no-cache curl

COPY nginx.conf /etc/nginx/nginx.conf

COPY default.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx","-g","daemon off;"]
