# Custom Apache HTTPD Docker Image for EFS

This directory contains a Dockerfile to build a custom Apache HTTPD image that runs as the `www` user (UID 2000), suitable for use with EFS.

## Build the image
```bash
docker build -t custom-httpd-efs .
```

## Run the container (example)
```bash
docker run -d --name my-httpd \
  -p 80:80 \
  -v /mnt/efs/www:/usr/local/apache2/htdocs/ \
  custom-httpd-efs
```

- The container runs as the `www` user (UID 2000).
- The EFS directory `/mnt/efs/www` should be owned by UID 2000 for write access.
