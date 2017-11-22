#!/bin/bash

set -e

echo -n "Checking for git "
if ! [ -x "$(command -v git)" ]; then
	echo "not found, installing "
    sudo apt-get install -qq -y git  > /tmp/git-install.log 2>&1
fi
echo "[✔]"

rm -f /tmp/*.log

cd /home/pi

this_file=$(readlink -f $0)
setup_file=/home/pi/davglass/setup.sh

before_md5=($(md5sum $this_file))

repos=(
    'https://togiles@bitbucket.org/togiles/lightshowpi.git'
    'https://github.com/davglass/lightshowpi.git ./davglass'
    'https://github.com/mikebrady/shairport-sync.git'
    'https://github.com/mikebrady/shairport-sync-metadata-reader.git'
)

if [ -z "$SKIP_CLONE" ]; then
	echo -n "Cloning all the repos needed: "
	for repo in "${repos[@]}"; do
		name=$(basename "$repo" .git)
		if [ -d "./${name}" ]; then
			cd ${name}
            git checkout -q master
            git fetch -q
            if [ $(git rev-parse HEAD) != $(git rev-parse @{u}) ]; then
                git pull -q
			    echo -n "↺ "
            else
                case "${repo}" in 
                    *togiles*)
                    SKIP_LIGHTSHOW_INSTALL=1
                    ;;
                    *shairport-sync.git*)
                    ##only care about main repo
                    SKIP_SHAIRPORT=1
                    ;;
                esac
                echo -n " ✔ "
            fi 
            cd ../
		else
			git clone -q ${repo}
			echo -n "✔ "
		fi
	done
	echo " done grabbing the code!"
fi

after_md5=($(md5sum $setup_file))

if [ -z "$SKIP_CHECK" ]; then
    echo -n "Checking if this script is up to date: "
    if [ "${before_md5}" != "$after_md5" ]; then
        echo "⚠ outdated, calling new file.."
        echo ""
        ${setup_file}
        exit
    else
        echo " [✔]"
    fi
else
    echo "⚠ Skipping up to date check"
fi

cd /home/pi
if [ -z "$SKIP_LIGHTSHOW_INSTALL" ]; then
	echo -n "Running lightshowpi setup, this may take a bit: "
	cd ./lightshowpi
	./install.sh > /tmp/lightshowpi-install.log 2>&1
	echo "[✔]"
else
    echo "⚠ Skipping lightshow install"
fi

if [ -z "$SKIP_SHAIRPORT" ]; then
	cd /home/pi
	echo -n "Installing shairport-sync deps: "
	sudo apt-get -qq -y install autoconf automake libtool libdaemon-dev libpopt-dev libconfig-dev libasound2-dev avahi-daemon libavahi-client-dev libssl-dev libsoxr-dev libsndfile1-dev >> /tmp/shairport-sync-install.log 2>&1
	echo "[✔]"

	cd /home/pi
	cd shairport-sync
	echo -n "Building shairport-sync from source: "
	autoreconf -i -f >> /tmp/shairport-sync-install.log 2>&1
	./configure --sysconfdir=/usr/local/etc --with-alsa --with-stdout --with-pipe --with-avahi --with-ssl=openssl --with-metadata --with-systemd >> /tmp/shairport-sync-install.log 2>&1
	make >> /tmp/shairport-sync-install.log
	echo "[✔]"

	cd /home/pi
	echo -n "Building shairport-sync-metadata-reader from source: "
	cd shairport-sync-metadata-reader
	autoreconf -i -f >> /tmp/shairport-sync-metadata-reader-install.log 2>&1
	./configure >> /tmp/shairport-sync-metadata-reader-install.log 2>&1
	make >> /tmp/shairport-sync-metadata-reader-install.log 2>&1
	sudo make install >> /tmp/shairport-sync-metadata-reader-install.log 2>&1
	echo "[✔]"
else
    echo "⚠ Skipping shairport install"
fi

if [ -z "$SKIP_DAVGLASS" ]; then
    echo "Setting up davglass additions: "
    cd /home/pi

    echo -n "   Installing packages "
    pip show tweepy 1>/dev/null
    if [ $? == 0 ]; then
        echo "⚠ (exists)"
    else
        sudo pip install tweepy >> /tmp/install.log 2>&1
        echo "[✔]"
    fi

    echo -n "   Linking configs & directories "
    if [ ! -s /home/pi/bin ]; then
        ln -sf /home/pi/davglass/bin /home/pi/bin
    fi
    if [ ! -s /home/pi/api ]; then
        ln -sf /home/pi/davglass/api /home/pi/api
    fi
    ln -sf /home/pi/davglass/.lights.cfg /home/pi/
    ln -sf /home/pi/.lights.cfg /home/pi/lightshowpi/config/overrides.cfg
    sudo ln -sf /home/pi/davglass/shairport-sync.conf /usr/local/etc/shairport-sync.conf

    echo "[✔]"

    git config --global user.email davglass@gmail.com
    git config --global user.name davglass

    cd lightshowpi
    echo -n "   Applying git patches "
    exists=`git branch --list davglass`
    if [ "$exists" != "" ]; then
        git checkout master >> /tmp/davglass.log 2>&1
        git branch -D davglass >> /tmp/davglass.log 2>&1
    fi
    git checkout -b davglass >> /tmp/davglass.log 2>&1
    git am < ../davglass/patches/0001-davglass-patches.patch >> /tmp/davglass.log 2>&1

    echo "[✔]"

    echo -n "   Configuring shell path "
    if grep -q "PATH=" /home/pi/.bashrc; then
        echo "⚠ (exists)"
    else
        echo "PATH=/home/pi/bin:\$PATH" >> /home/pi/.bashrc
        echo "[✔]"
    fi

    echo -n "   Configuring boot params "
    if grep -q boot\.sh /etc/rc.local; then
        echo "⚠ (exists)"
    else
        sudo sed -i '19i/home/pi/bin/boot.sh' /etc/rc.local
        echo "[✔]"
    fi

    echo -n "   Creating directories "
    dirs=(
        /home/pi/tmp
        /var/log/lights
        /var/log/api
    )
    for dir in "${dirs[@]}"; do
        sudo mkdir -p $dir
        sudo chmod a+w $dir
    done
    echo "[✔]"
else
    echo "⚠ Skipping shairport install"
fi

cd /home/pi

echo -n "   Starting services "
/home/pi/bin/stop_tweets > /tmp/setup-boot.log 2>&1
/home/pi/bin/stop_api >> /tmp/setup-boot.log 2>&1
/home/pi/bin/stop_lights >> /tmp/setup-boot.log 2>&1
/home/pi/bin/boot.sh >> /tmp/setup-boot.log 2>&1
echo "[✔]"

host=`hostname`
echo ""
echo "✔ All done, let's play!"
echo "  (you should probably reboot first to be safe)"
echo ""
echo "  Visit: http://${host}.local:8181/"
echo ""
