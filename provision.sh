#!/usr/bin/env bash
#
# Provisions an Ubuntu server with Rails 4, on Ruby 2.1.2, for a development environment.
#
# Requires:
#  - sudo privileges
#  - some Ruby pre installed & ERB 


# make script halt on failed commands
set -e

# protect against execution as root
if [ "$(id -u)" == "0" ]; then
   echo "Please run this script as a regular user with sudo privileges." 1>&2
   exit 1
fi


# =============================================================================
#   Variables
# =============================================================================

export DEBIAN_FRONTEND=noninteractive

# read variables from .env file if present
if [[ -e ./.env ]]; then
  . ./.env
  echo "(.env file detected and sourced)"
fi

# log file receiving all command output
PROVISION_TMP_DIR=${PROVISION_TMP_DIR:-"/tmp/rails-4-provisioner"}
LOG_FILE=$PROVISION_TMP_DIR/provision-$(date +%Y%m%d%H%M%S).log

# set Rails environment
export RAILS_ENV="${RAILS_ENV}"
export APP_HOSTNAME="${APP_HOSTNAME}"

# name of the Rails application to be installed
export APP_NAME=${APP_NAME:-"rails-4-app"}

# application's database details
export APP_DB_NAME=${APP_DB_NAME:-"rails_4_db"}
export APP_DB_USER=${APP_DB_USER:-"rails_4_user"}
export APP_DB_PASS=${APP_DB_PASS:-"cH4nG3_p455w0rD"} # you should provide your own passwords

export APP_TEST_DB_NAME=${APP_TEST_DB_NAME:-"rails_4_db_test"}
export APP_TEST_DB_USER=${APP_TEST_DB_USER:-"rails_4_user_test"}
export APP_TEST_DB_PASS=${APP_TEST_DB_PASS:-"cH4nG3_p455w0rD_test"}

# folder where the application will be installed
export APP_INSTALL_DIR=${APP_INSTALL_DIR}

echo "Provisioning for application: ${APP_INSTALL_DIR}, environment: ${RAILS_ENV}"


# =============================================================================
#   Bootstrap
# =============================================================================


# create the output log file
mkdir -p $PROVISION_TMP_DIR
touch $LOG_FILE
echo "Logging command output to $LOG_FILE"

# raising permissions for deploy user
  sudo /bin/bash -c "echo 'vagrant    ALL=(ALL:ALL) ALL' >> /etc/sudoers"

# update packages and install some dependencies and tools
echo "Updating packages..."
{
  sudo apt-get update
  sudo apt-get -y install build-essential zlib1g-dev curl libcurl4-openssl-dev git-core software-properties-common vim
} >> $LOG_FILE 2>&1

# =============================================================================
#   Install Ruby 2
# =============================================================================

if [[ -z $(ruby -v | grep 2.1.2) ]]; then
  # get Ruby source
  echo "Fetching ruby 2.1.2 ..."
  {
    wget http://cache.ruby-lang.org/pub/ruby/2.1/ruby-2.1.2.tar.gz
    tar xzf ruby-2.1.2.tar.gz
  } >> $LOG_FILE 2>&1

  # build it
  cd ruby-2.1.2
  echo "Building ruby 2.1.2 ..."
  {
    ./configure
    make
    sudo make install
    sudo gem update --system --no-document
  } >> $LOG_FILE 2>&1

  # install Rails 4
  echo "Installing Rails 4.1.1 ..."
  sudo gem install rails --version 4.1.1 --no-document >> $LOG_FILE 2>&1

  # cleanup
  cd ..
  rm -rf ruby-2.1.2*
fi

# =============================================================================
#   Web Server (Nginx)
# =============================================================================

# install Nginx web server
echo "Installing Nginx web server..."
{
  sudo apt-get install -y nginx
  sudo service nginx start
} >> $LOG_FILE 2>&1

echo "Creating nginx conf"
{
  erb templates/confs/nginx.conf.erb > $PROVISION_TMP_DIR/nginx.conf
  sudo /bin/bash -c "cat $PROVISION_TMP_DIR/nginx.conf > /etc/nginx/nginx.conf"
} >> $LOG_FILE 2>&1

echo "Creating default site"
{
  erb templates/confs/default.erb > $PROVISION_TMP_DIR/default
  # server_name should just be hostname
  sudo /bin/bash -c "cat $PROVISION_TMP_DIR/default > /etc/nginx/sites-enabled/default"
} >> $LOG_FILE 2>&1

echo "SSL for Nginx"
{
  sudo mkdir -p /etc/nginx/ssl
  sudo cp templates/ssl/server.crt /etc/nginx/ssl/server.crt
  sudo cp templates/ssl/server.key /etc/nginx/ssl/server.key
} >> $LOG_FILE 2>&1

echo "Restarting Nginx"
{
  sudo service nginx restart
} >> $LOG_FILE 2>&1

# =============================================================================
#  Redis
# =============================================================================

echo "Installing Redis"
{
  sudo apt-get install -y redis-server
  sudo service redis-server start
} >> $LOG_FILE 2>&1

# =============================================================================
#  Memcache
# =============================================================================
# installing memcache indexer
echo "Installing Memcache"
{
  sudo apt-get install -y memcached
  sudo service memcached start
} >> $LOG_FILE 2>&1

# =============================================================================
#   Database (PostgreSQL)
# =============================================================================

# install PostgreSQL
echo "Installing PostgreSQL..."
#sudo apt-get -y install postgresql postgresql-contrib libpq-dev >> $LOG_FILE 2>&1
sudo /bin/bash -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ precise-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y postgresql-9.3 postgresql-contrib-9.3 postgresql-server-dev-9.3 libpq-dev

# enable md5 auth for localhost
sudo /bin/bash -c "sed -i.bak 's/local   all             postgres                                peer/local   all                 postgres                                trust/g' /etc/postgresql/9.3/main/pg_hba.conf"
sudo /bin/bash -c "sed -i.bak 's/local   all             all                                     peer/local   all             all                                     trust/g' /etc/postgresql/9.3/main/pg_hba.conf"
sudo service postgresql restart

# change the default template encoding to utf8 or else Rails will complain
echo "Converting default database template encoding to utf8..."
sudo -u postgres psql < templates/sql/pg_utf8_template.sql >> $LOG_FILE 2>&1

# create application's database user
echo "Creating application's database users..."
erb templates/sql/pg_create_app_users.sql.erb > $PROVISION_TMP_DIR/pg_create_app_users.sql.repl
sudo -u postgres psql < $PROVISION_TMP_DIR/pg_create_app_users.sql.repl >> $LOG_FILE 2>&1


# =============================================================================
#   Javascript Runtime (Node.js)
# =============================================================================

# install node.js as a javascript runtime for rails
echo "Installing Node.js as the javascript runtime..."
{
  sudo apt-get -y install python-software-properties python
  sudo add-apt-repository -y ppa:chris-lea/node.js
  sudo apt-get update
  sudo apt-get -y install nodejs
} >> $LOG_FILE 2>&1

# =============================================================================
#   Elasticsearch
# =============================================================================
# installing elasticsearch indexer
# https://gist.github.com/wingdspur/2026107
echo "Installing Elasticsearch..."
{
  sudo apt-get install openjdk-7-jre-headless -y
 
 ### Check http://www.elasticsearch.org/download/ for latest version of ElasticSearch and replace wget link below
  wget https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-1.3.2.deb
  sudo dpkg -i elasticsearch-1.3.2.deb
  sudo update-rc.d elasticsearch defaults 95 10
  sudo /etc/init.d/elasticsearch start
} >> $LOG_FILE 2>&1


# =============================================================================
#   Install Rails App
# =============================================================================

cd $APP_INSTALL_DIR

# install application's gems
echo "Installing application's gems..."
cd $APP_INSTALL_DIR
bundle install >> $LOG_FILE 2>&1

# =============================================================================
#  Unicorn 
# =============================================================================

echo "Installing unicorn as a service" 
{
  erb templates/confs/unicornd.conf.erb > $PROVISION_TMP_DIR/unicornd.conf
  sudo /bin/bash -c "cat $PROVISION_TMP_DIR/unicornd.conf > /etc/init/unicornd.conf"
  sudo /bin/bash -c "chmod 0644 /etc/init/unicornd.conf"
  sudo /bin/bash -c "chown root:root /etc/init/unicornd.conf"

} >> $LOG_FILE 2>&1

echo "Writing unicorn conf" 
{
  erb templates/confs/unicorn.rb.erb > $PROVISION_TMP_DIR/unicorn.rb
  sudo /bin/bash -c "cat $PROVISION_TMP_DIR/unicorn.rb > $APP_INSTALL_DIR/config/unicorn.rb"
} >> $LOG_FILE 2>&1

# create databases
echo "Initializing application's database..."
{
  RAILS_ENV=production bundle exec rake db:create
  #bundle exec rake db:schema:load
  #RAILS_ENV=production bundle exec rake db:migrate
  # Line will fail with rails-4-vagrant not in root
  #RAILS_ENV=production bundle exec rake indexers:all
  return 0;
} >> $LOG_FILE 2>&1

echo "__FINISHED__"

#echo "Installing unicorn as a service" {
  #cd $APP_INSTALL_DIR
  #sudo -E bundle exec unicorn_rails -E production -c ./config/unicorn.rb &
#} >> $LOG_FILE 2>&1


echo "Provisioning completed successfully!"
exit 0
