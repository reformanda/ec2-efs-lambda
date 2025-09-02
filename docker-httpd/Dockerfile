# Custom Apache HTTPD Dockerfile for EFS
FROM httpd:2.4

# Set maintainer label
LABEL maintainer="your-email@example.com"


# Create www user with UID 2000
RUN useradd -u 2000 -m www

# Set working directory to Apache web root
WORKDIR /usr/local/apache2/htdocs

# Change ownership of web root and logs to www
RUN chown -R www:www /usr/local/apache2/htdocs /usr/local/apache2/logs

# Switch to www user
USER www

# Expose port 80
EXPOSE 80

# Entrypoint and CMD are inherited from httpd base image
