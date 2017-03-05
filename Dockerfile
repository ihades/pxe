FROM stackbrew/debian:jessie
ENV ARCH amd64
ENV DIST jessie
ENV MIRROR http://ftp.nl.debian.org
RUN apt-get -q update
RUN apt-get -qy install dnsmasq wget iptables gzip
RUN wget --no-check-certificate https://raw.github.com/jpetazzo/pipework/master/pipework
RUN chmod +x pipework
# Splash-Screen
RUN mkdir /tftp
WORKDIR /tftp
RUN wget $MIRROR/debian/dists/$DIST/main/installer-$ARCH/current/images/netboot/debian-installer/$ARCH/boot-screens/vesamenu.c32
RUN wget $MIRROR/debian/dists/$DIST/main/installer-$ARCH/current/images/netboot/debian-installer/$ARCH/pxelinux.0
# DEBIAN
RUN mkdir /tftp/debian
WORKDIR /tftp/debian
RUN wget $MIRROR/debian/dists/$DIST/main/installer-$ARCH/current/images/netboot/debian-installer/$ARCH/linux
RUN wget $MIRROR/debian/dists/$DIST/main/installer-$ARCH/current/images/netboot/debian-installer/$ARCH/initrd.gz
# MEMTEST
RUN mkdir /tftp/memtest
WORKDIR /tftp/memtest
RUN wget http://www.memtest.org/download/5.01/memtest86+-5.01.bin.gz
RUN gunzip memtest86+-5.01.bin.gz
RUN mv memtest86+-5.01.bin memtest86
# Make PXE-Configuration
RUN mkdir pxelinux.cfg
RUN echo "DEFAULT menu.c32
ALLOWOPTIONS 0
PROMPT 0
TIMEOUT 0

MENU TITLE Server PXE Boot Server

LABEL      memtest
MENU LABEL ^Memtest86+
KERNEL     memtest/memtest86

LABEL debian-install
MENU LABEL Install ^Debian
KERNEL debian/linux26
APPEND initrd=initrd.gz

label proxmox-install
menu label ^Install Proxmox
linux proxmox/linux26
append vga=791 video=vesafb:ywrap,mtrr ramdisk_size=16777216 rw quiet splash=silent
initrd proxmox/initrd.iso.img splash=verbose

label proxmox-debug-install
menu label Install ^Proxmox (Debug Mode)
linux proxmox/linux26
append vga=791 video=vesafb:ywrap,mtrr ramdisk_size=16777216 rw quiet splash=verbose proxdebug
initrd proxmox/initrd.iso.img splash=verbose
" >> pxelinux.cfg/default

CMD \
    echo Setting up iptables... &&\
    iptables -t nat -A POSTROUTING -j MASQUERADE &&\
    echo Waiting for pipework to give us the eth1 interface... &&\
    /pipework --wait &&\
    myIP=$(ip addr show dev eth1 | awk -F '[ /]+' '/global/ {print $3}') &&\
    mySUBNET=$(echo $myIP | cut -d '.' -f 1,2,3) &&\
    echo Starting DHCP+TFTP server...&&\
    dnsmasq --interface=eth1 \
    	    --dhcp-range=$mySUBNET.101,$mySUBNET.199,255.255.255.0,1h \
	    --dhcp-boot=pxelinux.0,pxeserver,$myIP \
	    --pxe-service=x86PC,"Install Linux",pxelinux \
	    --enable-tftp --tftp-root=/tftp/ --no-daemon
# Let's be honest: I don't know if the --pxe-service option is necessary.
# The iPXE loader in QEMU boots without it.  But I know how some PXE ROMs
# can be picky, so I decided to leave it, since it shouldn't hurt.
