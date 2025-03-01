#!/bin/bash

# Script to set up and harden Apache2 test server on Ubuntu with troubleshooting
# Run as root (sudo)

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo)"
    echo "TROUBLESHOOTING: Use 'sudo ./script.sh' to execute with proper permissions"
    exit 1
fi

# Update system and install Apache2
echo "Updating system and installing Apache2..."
if ! apt update && apt upgrade -y; then
    echo "ERROR: System update failed"
    echo "TROUBLESHOOTING: Check internet connection and apt sources (/etc/apt/sources.list)"
    exit 1
fi

if ! apt install -y apache2; then
    echo "ERROR: Apache2 installation failed"
    echo "TROUBLESHOOTING: Check apt logs in /var/log/apt/ and ensure sufficient disk space"
    exit 1
fi

# Create test server directory structure
echo "Setting up test server structure..."
if ! mkdir -p /var/www/test-server; then
    echo "ERROR: Failed to create test server directory"
    echo "TROUBLESHOOTING: Check disk space and permissions on /var/www/"
    exit 1
fi

if ! chown -R www-data:www-data /var/www/test-server || ! chmod 755 /var/www/test-server; then
    echo "ERROR: Failed to set test server permissions"
    echo "TROUBLESHOOTING: Verify www-data user exists and has proper privileges"
    exit 1
fi

# Create test page
echo "Creating test page..."
cat > /var/www/test-server/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Apache Test Server</title>
</head>
<body>
    <h1>Apache Test Server</h1>
    <p>This is a test server running on Apache2</p>
    <p>Server Time: $(date)</p>
</body>
</html>
EOF

# Configure test site
echo "Configuring test site..."
cat > /etc/apache2/sites-available/test-server.conf << 'EOF'
<VirtualHost *:80>
    ServerName test-server.local
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/test-server
    
    <Directory /var/www/test-server>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog ${APACHE_LOG_DIR}/test-server-error.log
    CustomLog ${APACHE_LOG_DIR}/test-server-access.log combined
</VirtualHost>
EOF

# Enable the test site
echo "Enabling test site..."
if ! a2ensite test-server.conf || ! a2dissite 000-default.conf; then
    echo "ERROR: Failed to enable test site configuration"
    echo "TROUBLESHOOTING: Check syntax in /etc/apache2/sites-available/test-server.conf"
    exit 1
fi

# Test initial configuration
echo "Testing initial configuration..."
if ! apache2ctl configtest; then
    echo "ERROR: Initial Apache configuration test failed"
    echo "TROUBLESHOOTING: Check /var/log/apache2/error.log for specific errors"
    exit 1
fi

if ! systemctl restart apache2; then
    echo "ERROR: Failed to restart Apache after initial setup"
    echo "TROUBLESHOOTING: Check systemctl status apache2 and journalctl -xe"
    exit 1
fi
echo "Test server setup complete. Access it at http://localhost/"

# Backup Apache configuration
echo "Backing up Apache configuration..."
if ! cp -r /etc/apache2 /etc/apache2.backup-$(date +%Y%m%d); then
    echo "ERROR: Failed to create backup"
    echo "TROUBLESHOOTING: Check disk space and permissions on /etc/"
    exit 1
fi

# Install security modules
echo "Installing security modules..."
if ! apt install -y libapache2-mod-security2 libapache2-mod-evasive; then
    echo "ERROR: Failed to install security modules"
    echo "TROUBLESHOOTING: Check apt logs and internet connection"
    exit 1
fi

# Enable modules
echo "Enabling Apache modules..."
for module in headers security2 evasive ssl rewrite; do
    if ! a2enmod $module; then
        echo "ERROR: Failed to enable $module module"
        echo "TROUBLESHOOTING: Verify module exists in /etc/apache2/mods-available/"
        exit 1
    fi
done

# Create security configuration
echo "Creating security configuration..."
cat > /etc/apache2/conf-available/security.conf << 'EOF'
# Security Headers
Header set X-Content-Type-Options "nosniff"
Header set X-Frame-Options "DENY"
Header set X-XSS-Protection "1; mode=block"
Header set Referrer-Policy "strict-origin-when-cross-origin"
Header set Content-Security-Policy "default-src 'self'"

# Disable directory listing
Options -Indexes

# Disable server signature
ServerSignature Off
ServerTokens Prod

# Set timeout values
Timeout 30
KeepAliveTimeout 5

# ModEvasive configuration
DOSHashTableSize 3097
DOSPageCount 2
DOSSiteCount 50
DOSPageInterval 1
DOSSiteInterval 1
DOSBlockingPeriod 10
EOF

if ! a2enconf security; then
    echo "ERROR: Failed to enable security configuration"
    echo "TROUBLESHOOTING: Check syntax in /etc/apache2/conf-available/security.conf"
    exit 1
fi

# Configure ModSecurity
echo "Configuring ModSecurity..."
if ! cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf; then
    echo "ERROR: Failed to copy ModSecurity configuration"
    echo "TROUBLESHOOTING: Verify modsecurity package installed correctly"
    exit 1
fi

if ! sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/modsecurity/modsecurity.conf; then
    echo "ERROR: Failed to modify ModSecurity configuration"
    echo "TROUBLESHOOTING: Check write permissions on /etc/modsecurity/modsecurity.conf"
    exit 1
fi

# Install OWASP CRS
echo "Installing OWASP Core Rule Set..."
if ! apt install -y modsecurity-crs || ! ln -s /usr/share/modsecurity-crs /etc/modsecurity/crs; then
    echo "ERROR: Failed to install or configure OWASP CRS"
    echo "TROUBLESHOOTING: Check package availability and permissions"
    exit 1
fi

# Configure ModEvasive
echo "Configuring ModEvasive..."
if ! mkdir -p /var/log/mod_evasive; then
    echo "ERROR: Failed to create ModEvasive log directory"
    echo "TROUBLESHOOTING: Check disk space and permissions on /var/log/"
    exit 1
fi

cat > /etc/apache2/mods-available/evasive.conf << 'EOF'
<IfModule mod_evasive20.c>
    DOSHashTableSize    3097
    DOSPageCount        2
    DOSSiteCount        50
    DOSPageInterval     1
    DOSSiteInterval     1
    DOSBlockingPeriod   10
    DOSLogDir           "/var/log/mod_evasive"
    DOSEmailNotify      "admin@yourdomain.com"
    DOSWhitelist        127.0.0.1
</IfModule>
EOF

# Set permissions
echo "Setting file permissions..."
if ! chown -R root:root /etc/apache2 || ! chmod -R 640 /etc/apache2; then
    echo "ERROR: Failed to set Apache config permissions"
    echo "TROUBLESHOOTING: Check filesystem permissions"
    exit 1
fi

if ! chown www-data:www-data /var/www/test-server || ! chown www-data:www-data /var/log/mod_evasive || ! chmod 750 /var/log/mod_evasive; then
    echo "ERROR: Failed to set runtime permissions"
    echo "TROUBLESHOOTING: Verify www-data user and group exist"
    exit 1
fi

# Restrict HTTP methods
echo "Restricting HTTP methods..."
cat > /etc/apache2/conf-available/restrict-methods.conf << 'EOF'
<Directory /var/www/test-server>
    RewriteEngine On
    RewriteCond %{REQUEST_METHOD} ^(TRACE|TRACK|OPTIONS|PUT|DELETE)
    RewriteRule .* - [F]
</Directory>
EOF

if ! a2enconf restrict-methods; then
    echo "ERROR: Failed to enable HTTP method restrictions"
    echo "TROUBLESHOOTING: Check syntax in restrict-methods.conf"
    exit 1
fi

# Configure SSL
echo "Configuring SSL parameters..."
cat > /etc/apache2/conf-available/ssl-params.conf << 'EOF'
SSLCipherSuite EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH
SSLProtocol All -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
SSLHonorCipherOrder On
SSLCompression off
SSLSessionTickets Off
EOF

if ! a2enconf ssl-params; then
    echo "ERROR: Failed to enable SSL parameters"
    echo "TROUBLESHOOTING: Check syntax in ssl-params.conf"
    exit 1
fi

# Final configuration test
echo "Testing final Apache configuration..."
if ! apache2ctl configtest; then
    echo "ERROR: Final configuration test failed"
    echo "TROUBLESHOOTING: Check /var/log/apache2/error.log and run 'apache2ctl configtest' manually"
    exit 1
fi

if ! systemctl restart apache2; then
    echo "ERROR: Failed to restart Apache after hardening"
    echo "TROUBLESHOOTING: Check 'systemctl status apache2' and '/var/log/apache2/error.log'"
    exit 1
fi

echo "Apache test server setup and hardening completed successfully!"
echo "Test server is running at http://localhost/"

# Display final instructions
echo -e "\nFinal Instructions and Recommendations:"
echo "1. Access test server at http://localhost/"
echo "2. Replace 'admin@yourdomain.com' in /etc/apache2/mods-available/evasive.conf"
echo "3. Configure SSL certificates for production use"
echo "4. Add '127.0.0.1 test-server.local' to /etc/hosts to access via domain name"
echo "5. Monitor logs in /var/log/apache2/ and /var/log/mod_evasive/"
