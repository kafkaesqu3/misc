#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "Please run this script as root" 1>&2
	exit 1
fi

### Functions ###

debian_initialize() {
	echo "Updating and Installing Dependicies"
	apt-get -qq update > /dev/null 2>&1
	apt-get -qq -y upgrade > /dev/null 2>&1
	apt-get install -qq -y nmap > /dev/null 2>&1
	apt-get install -qq -y git > /dev/null 2>&1
	apt-get remove -qq -y exim4 exim4-base exim4-config exim4-daemon-light > /dev/null 2>&1
	rm -r /var/log/exim4/ > /dev/null 2>&1

	update-rc.d nfs-common disable > /dev/null 2>&1
	update-rc.d rpcbind disable > /dev/null 2>&1

	echo "IPv6 Disabled"

	cat <<-EOF >> /etc/sysctl.conf
	net.ipv6.conf.all.disable_ipv6 = 1
	net.ipv6.conf.default.disable_ipv6 = 1
	net.ipv6.conf.lo.disable_ipv6 = 1
	net.ipv6.conf.eth0.disable_ipv6 = 1
	net.ipv6.conf.eth1.disable_ipv6 = 1
	net.ipv6.conf.ppp0.disable_ipv6 = 1
	net.ipv6.conf.tun0.disable_ipv6 = 1

	EOF

	sysctl -p > /dev/null 2>&1

	echo "Changing Hostname"

	read -p "Enter your hostname: " -r primary_domain

	cat <<-EOF > /etc/hosts
	127.0.1.1 $primary_domain $primary_domain
	127.0.0.1 localhost
	EOF

	cat <<-EOF > /etc/hostname
	$primary_domain
	EOF

	echo "The System will now reboot!"
	reboot
}

ubuntu_initialize() {
	echo "Updating and Installing Dependicies"
	apt-get -qq update > /dev/null 2>&1
	apt-get -qq -y upgrade > /dev/null 2>&1
	apt-get install -qq -y nmap > /dev/null 2>&1
	apt-get install -qq -y git > /dev/null 2>&1
	rm -r /var/log/exim4/ > /dev/null 2>&1

	update-rc.d nfs-common disable > /dev/null 2>&1
	update-rc.d rpcbind disable > /dev/null 2>&1

	echo "IPv6 Disabled"

	cat <<-EOF >> /etc/sysctl.conf
	net.ipv6.conf.all.disable_ipv6 = 1
	net.ipv6.conf.default.disable_ipv6 = 1
	net.ipv6.conf.lo.disable_ipv6 = 1
	net.ipv6.conf.eth0.disable_ipv6 = 1
	net.ipv6.conf.eth1.disable_ipv6 = 1
	net.ipv6.conf.ppp0.disable_ipv6 = 1
	net.ipv6.conf.tun0.disable_ipv6 = 1
	EOF

	sysctl -p > /dev/null 2>&1

	echo "Changing Hostname"

	read -p "Enter your hostname: " -r primary_domain

	cat <<-EOF > /etc/hosts
	127.0.1.1 $primary_domain $primary_domain
	127.0.0.1 localhost
	EOF

	cat <<-EOF > /etc/hostname
	$primary_domain
	EOF

	echo "The System will now reboot!"
	reboot
}

add_firewall_port(){
	read -p "Enter the port you would like opened: " -r port
	iptables -A INPUT -p tcp --dport ${port} -j ACCEPT
	iptables -A OUTPUT -p tcp --sport ${port} -j ACCEPT
	iptables-save
}


install_ssl_Cert() {
	git clone https://github.com/certbot/certbot.git /opt/letsencrypt > /dev/null 2>&1

	cd /opt/letsencrypt
	letsencryptdomains=()
	end="false"
	i=0
	
	while [ "$end" != "true" ]
	do
		read -p "Enter your server's domain or done to exit: " -r domain
		if [ "$domain" != "done" ]
		then
			letsencryptdomains[$i]=$domain
		else
			end="true"
		fi
		((i++))
	done
	command="./certbot-auto certonly --standalone "
	for i in "${letsencryptdomains[@]}";
		do
			command="$command -d $i"
		done
	command="$command -n --register-unsafely-without-email --agree-tos"
	
	eval $command

}

install_postfix_dovecot() {
	echo "Installing Dependicies"
	apt-get install -qq -y dovecot-imapd dovecot-lmtpd
	apt-get install -qq -y postfix postgrey postfix-policyd-spf-python
	apt-get install -qq -y opendkim opendkim-tools
	apt-get install -qq -y opendmarc
	apt-get install -qq -y mailutils

	read -p "Enter your mail server's domain: " -r primary_domain
	read -p "Enter IP's to allow Relay (if none just hit enter): " -r relay_ip
	echo "Configuring Postfix"

	cat <<-EOF > /etc/postfix/main.cf
	smtpd_banner = \$myhostname ESMTP \$mail_name (Debian/GNU)
	biff = no
	append_dot_mydomain = no
	readme_directory = no
	smtpd_tls_cert_file=/etc/letsencrypt/live/${primary_domain}/fullchain.pem
	smtpd_tls_key_file=/etc/letsencrypt/live/${primary_domain}/privkey.pem
	smtpd_tls_security_level = may
	smtp_tls_security_level = encrypt
	smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
	smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache
	smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
	myhostname = ${primary_domain}
	alias_maps = hash:/etc/aliases
	alias_database = hash:/etc/aliases
	myorigin = /etc/mailname
	mydestination = ${primary_domain}, localhost.com, , localhost
	relayhost =
	mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128 ${relay_ip}
	mailbox_command = procmail -a "\$EXTENSION"
	mailbox_size_limit = 0
	recipient_delimiter = +
	inet_interfaces = all
	inet_protocols = ipv4
	milter_default_action = accept
	milter_protocol = 6
	smtpd_milters = inet:12301,inet:localhost:54321
	non_smtpd_milters = inet:12301,inet:localhost:54321
	EOF

	cat <<-EOF >> /etc/postfix/master.cf
	submission inet n       -       -       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_wrappermode=no
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_recipient_restrictions=permit_mynetworks,permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
	EOF

	echo "Configuring Opendkim"

	mkdir -p "/etc/opendkim/keys/${primary_domain}"
	cp /etc/opendkim.conf /etc/opendkim.conf.orig

	cat <<-EOF > /etc/opendkim.conf
	domain								*
	AutoRestart						Yes
	AutoRestartRate				10/1h
	Umask									0002
	Syslog								Yes
	SyslogSuccess					Yes
	LogWhy								Yes
	Canonicalization			relaxed/simple
	ExternalIgnoreList		refile:/etc/opendkim/TrustedHosts
	InternalHosts					refile:/etc/opendkim/TrustedHosts
	KeyFile								/etc/opendkim/keys/${primary_domain}/mail.private
	Selector							mail
	Mode									sv
	PidFile								/var/run/opendkim/opendkim.pid
	SignatureAlgorithm		rsa-sha256
	UserID								opendkim:opendkim
	Socket								inet:12301@localhost
	EOF

	cat <<-EOF > /etc/opendkim/TrustedHosts
	127.0.0.1
	localhost
	${primary_domain}
	${relay_ip}
	EOF

	cd "/etc/opendkim/keys/${primary_domain}" || exit
	opendkim-genkey -s mail -d "${primary_domain}"
	echo 'SOCKET="inet:12301"' >> /etc/default/opendkim
	chown -R opendkim:opendkim /etc/opendkim

	echo "Configuring opendmarc"

	cat <<-EOF > /etc/opendmarc.conf
	AuthservID ${primary_domain}
	PidFile /var/run/opendmarc.pid
	RejectFailures false
	Syslog true
	TrustedAuthservIDs ${primary_domain}
	Socket  inet:54321@localhost
	UMask 0002
	UserID opendmarc:opendmarc
	IgnoreHosts /etc/opendmarc/ignore.hosts
	HistoryFile /var/run/opendmarc/opendmarc.dat
	EOF

	mkdir "/etc/opendmarc/"
	echo "localhost" > /etc/opendmarc/ignore.hosts
	chown -R opendmarc:opendmarc /etc/opendmarc

	echo 'SOCKET="inet:54321"' >> /etc/default/opendmarc

	echo "Configuring Dovecot"

	cat <<-EOF > /etc/dovecot/dovecot.conf
	disable_plaintext_auth = no
	mail_privileged_group = mail
	mail_location = mbox:~/mail:INBOX=/var/mail/%u

	userdb {
	  driver = passwd
	}

	passdb {
	  args = %s
	  driver = pam
	}

	protocols = " imap"

	protocol imap {
	  mail_plugins = " autocreate"
	}

	plugin {
	  autocreate = Trash
	  autocreate2 = Sent
	  autosubscribe = Trash
	  autosubscribe2 = Sent
	}

	service imap-login {
	  inet_listener imap {
	    port = 0
	  }
	  inet_listener imaps {
	    port = 993
	  }
	}

	service auth {
	  unix_listener /var/spool/postfix/private/auth {
	    group = postfix
	    mode = 0660
	    user = postfix
	  }
	}

	ssl=required
	ssl_cert = </etc/letsencrypt/live/${primary_domain}/fullchain.pem
	ssl_key = </etc/letsencrypt/live/${primary_domain}/privkey.pem
	EOF

	read -p "What user would you like to assign to recieve email for Root: " -r user_name
	echo "${user_name}: root" >> /etc/aliases
	echo "Root email assigned to ${user_name}"

	echo "Restarting Services"
	service postfix restart
	service opendkim restart
	service opendmarc restart
	service dovecot restart

	echo "Checking Service Status"
	service postfix status
	service opendkim status
	service opendmarc status
	service dovecot status
}

function add_alias(){
	read -p "What email address do you want to assign: " -r email_address
	read -p "What user do you want to assign to that email address: " -r user
	echo "${email_address}: ${user}" >> /etc/aliases
	newaliases
	echo "${email_address} assigned to ${user}"
}

function get_dns_entries(){
	extip=$(ifconfig|grep 'Link encap\|inet '|awk '!/Loopback|:127./'|tr -s ' '|grep 'inet'|tr ':' ' '|cut -d" " -f4)
	domain=$(ls /etc/opendkim/keys/ | head -1)
	fields=$(echo "${domain}" | tr '.' '\n' | wc -l)
	dkimrecord=$(cut -d '"' -f 2 "/etc/opendkim/keys/${domain}/mail.txt" | tr -d "[:space:]")

	if [[ $fields -eq 2 ]]; then
		cat <<-EOF > dnsentries.txt
		DNS Entries for ${domain}:

		====================================================================
		Namecheap - Enter under Advanced DNS

		Record Type: A
		Host: @
		Value: ${extip}
		TTL: 5 min

		Record Type: TXT
		Host: @
		Value: v=spf1 ip4:${extip} -all
		TTL: 5 min

		Record Type: TXT
		Host: mail._domainkey
		Value: ${dkimrecord}
		TTL: 5 min

		Record Type: TXT
		Host: ._dmarc
		Value: v=DMARC1; p=reject
		TTL: 5 min

		Change Mail Settings to Custom MX and Add New Record
		Record Type: MX
		Host: @
		Value: ${domain}
		Priority: 10
		TTL: 5 min
		EOF
		cat dnsentries.txt
	else
		prefix=$(echo "${domain}" | rev | cut -d '.' -f 3- | rev)
		cat <<-EOF > dnsentries.txt
		DNS Entries for ${domain}:

		====================================================================
		Namecheap - Enter under Advanced DNS

		Record Type: A
		Host: ${prefix}
		Value: ${extip}
		TTL: 5 min

		Record Type: TXT
		Host: ${prefix}
		Value: v=spf1 ip4:${extip} -all
		TTL: 5 min

		Record Type: TXT
		Host: mail._domainkey.${prefix}
		Value: ${dkimrecord}
		TTL: 5 min

		Record Type: TXT
		Host: ._dmarc
		Value: v=DMARC1; p=reject
		TTL: 5 min

		Change Mail Settings to Custom MX and Add New Record
		Record Type: MX
		Host: ${prefix}
		Value: ${domain}
		Priority: 10
		TTL: 5 min
		EOF
		cat dnsentries.txt
	fi

}

setupSSH(){
	apt-get -qq -y install sudo > /dev/null 2>&1
	apt-get -qq -y install fail2ban > /dev/null 2>&1

	echo "Create a User to ssh into this system securely"

	read -p "Enter your user name: " -r user_name

	adduser $user_name

	usermod -aG sudo $user_name

	cat <<-EOF > /etc/ssh/sshd_config
	Port 22
	Protocol 2
	HostKey /etc/ssh/ssh_host_rsa_key
	HostKey /etc/ssh/ssh_host_dsa_key
	HostKey /etc/ssh/ssh_host_ecdsa_key
	#Privilege Separation is turned on for security
	UsePrivilegeSeparation yes
	KeyRegenerationInterval 3600
	ServerKeyBits 1024
	SyslogFacility AUTH
	LogLevel INFO
	LoginGraceTime 120
	PermitRootLogin no
	StrictModes yes
	RSAAuthentication yes
	PubkeyAuthentication yes
	IgnoreRhosts yes
	RhostsRSAAuthentication no
	HostbasedAuthentication no
	PermitEmptyPasswords no
	ChallengeResponseAuthentication no
	PasswordAuthentication no
	X11Forwarding yes
	X11DisplayOffset 10
	PrintMotd no
	PrintLastLog yes
	TCPKeepAlive yes
	Banner no
	AcceptEnv LANG LC_*
	Subsystem sftp /usr/lib/openssh/sftp-server
	UsePAM no
	EOF


	echo "AllowUsers ${user_name}" > /etc/ssh/sshd_config

	cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

	cd /home/$user_name
	runuser -l $user_name -c "mkdir '.ssh'"
	runuser -l $user_name -c "chmod 700 ~/.ssh"

	runuser -l $user_name -c "echo ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC6qzer9yq+oSioEr3ZPpvspvJUzaz/gTfKXMSKUjS64IycIZ1fwPKBUaT1AB5UJM6WmbOPk9Hn0H3nA7Go9LNXmULE1iik3Ppnsdlnh5kSr8Pk4tr1UJPJ/JbzOmietZQpno1mqLL8R+9fb4pzqiTXUT2bOaoy/RPocmHeu8x/UHgU2TQFDzXOi5GkAxCS7RGKc5yIbBbXaSoxasR3CwjnvNOlxwWGB+tCzH13zaBhqPSpLwioosa3+MkkeJncvuwQgoqMbDlSs/jGi56H9OtD8dygEIXmcIYHv8PaP2YVuLG0S2nd4ZtcNFiOIfUyfP0v9Myl90rQ7AVf/les34iR david@trcadmins-MacBook-Pro.local >> ~/.ssh/authorized_keys"

	service ssh restart

}

function Install_GoPhish {
	apt-get install unzip > /dev/null 2>&1
	wget https://github.com/gophish/gophish/releases/download/v0.4.0/gophish-v0.4-linux-64bit.zip
	unzip gophish-v0.4-linux-64bit.zip
	cd gophish-v0.4-linux-64bit
        sed -i 's/"listen_url" : "127.0.0.1:3333"/"listen_url" : "0.0.0.0:3333"/g' config.json
	read -r -p "Do you want to add an SSL certificate to your GoPhish? [y/N] " response
	case "$response" in
	[yY][eE][sS]|[yY])
        	 read -p "Enter your web server's domain: " -r primary_domain
		 if [ -f "/etc/letsencrypt/live/${primary_domain}/fullchain.pem" ];then
		 	ssl_cert="/etc/letsencrypt/live/${primary_domain}/fullchain.pem"
       		 	ssl_key="/etc/letsencrypt/live/${primary_domain}/privkey.pem"
       		 	cp $ssl_cert ${primary_domain}.crt
        	 	cp $ssl_key ${primary_domain}.key
        	 	sed -i "s/0.0.0.0:80/0.0.0.0:443/g" config.json
        	 	sed -i "s/gophish_admin.crt/${primary_domain}.crt/g" config.json
        	 	sed -i "s/gophish_admin.key/${primary_domain}.key/g" config.json
			sed -i 's/"use_tls" : false/"use_tls" : true/g' config.json
        	 	sed -i "s/example.crt/${primary_domain}.crt/g" config.json
        	 	sed -i "s/example.key/${primary_domain}.key/g" config.json
		 else
			echo "Certificate not found, use Install SSL option first"
		 fi
       		 ;;
    	*)
        	echo "GoPhish installed"
        	;;
	esac
}


function Install_IRedMail {
	echo "Downloading iRedMail"
	wget https://bitbucket.org/zhb/iredmail/downloads/iRedMail-0.9.7.tar.bz2
	tar -xvf iRedMail-0.9.7.tar.bz2
	cd iRedMail-0.9.7/
	chmod +x iRedMail.sh
	echo "Running iRedMail Installer"
	./iRedMail.sh

	cat <<-EOF > /etc/apache2/ports.conf
# If you just change the port or add more ports here, you will likely also
# have to change the VirtualHost statement in
# /etc/apache2/sites-enabled/000-default.conf

Listen 8080

<IfModule ssl_module>
	Listen 8443
</IfModule>

<IfModule mod_gnutls.c>
	Listen 8443
</IfModule>
	EOF
	sed -i "/<VirtualHost/c\<VirtualHost *:8080>" /etc/apache2/sites-enabled/000-default.conf
	sed -i "/<VirtualHost _default_:/c\<VirtualHost _default_:8443>" /etc/apache2/sites-enabled/default-ssl.conf

	service apache2 restart
	
}

PS3="Server Setup Script - Pick an option: "
options=("Setup SSH" "Debian Prep" "Ubuntu Prep" "Install SSL" "Install Mail Server" "Add Aliases" "Get DNS Entries" "Install GoPhish" "Install IRedMail" "IPTables config")
select opt in "${options[@]}" "Quit"; do

    case "$REPLY" in

    #Prep
    1) setupSSH;;

		2) debian_initialize;;

		3) ubuntu_initialize;;

		4) install_ssl_Cert;;

		5) install_postfix_dovecot;;

		6) add_alias;;

		7) get_dns_entries;;

		8) Install_GoPhish;;

		9) Install_IRedMail;;

		10) reset_firewall;;

    $(( ${#options[@]}+1 )) ) echo "Goodbye!"; break;;
    *) echo "Invalid option. Try another one.";continue;;

    esac

done