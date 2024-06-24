# Kernel and Firmware version to use when building Phonebo.Cx Kernel
KVERS=6.6.25
KMAJOR=$(word 1,$(subst ., ,$(KVERS)))
KMINOR=$(word 2,$(subst ., ,$(KVERS)))
KREV=$(word 3,$(subst ., ,$(KVERS)))
VERS=1
KFIRMWARE=20240610

ORIG=src/linux-$(KVERS).tar.xz
FORIG=src/linux-firmware-$(KFIRMWARE).tar.gz
DEST=kernel/linux-$(KVERS)
FDEST=kernel/linux-firmware-$(KFIRMWARE)
DIR=$(shell pwd)
SHELL=/bin/bash
export KERNELREV DEST DIR

.PHONY: all clean distclean setup modules deb patch unpatch sgm-dahdi firmware test
DPKG_FLAGS=-Zgzip
export DPKG_FLAGS

DESTDEB=kernel/linux-image-$(KVERS)-$(VERS)_$(KVERS)-$(VERS)_amd64.deb
# PhoneBo.cx git repo, sgm branch.
DAHDI_SRC=src/dahdi-linux

test: $(DESTDEB)
	# If this fails, the kernel did not build Dahdi or our USB device
	@dpkg-deb --contents $<  | grep ua32xx.ko && echo ua32xx.ko found
	@dpkg-deb --contents $< | grep dahdi.ko && echo dahdi.ko found

clean:
	[ -d $(DIR)/kernel ] && cd $(DIR)/kernel && rm -rf * || :

distclean: clean
	rm -rf $(DEST) $(FDEST) $(DAHDI_SRC)

firmware: $(FORIG)
	mkdir -p $(FDEST) && \
		tar -C $(FDEST) --strip-components=1 -xf $(FORIG)

setup: /usr/bin/ccache /usr/bin/gcc $(DEST)/.config patch
	@if ! grep -q DAHDI $(DEST)/.config; then echo ".config has no DAHDI lines"; exit 1; fi

/usr/bin/ccache:
	apt-get -y install ccache

.PHONY: packages
packages /usr/bin/gcc:
	apt-get -y install build-essential flex bison libelf-dev libssl-dev bc debhelper libelf-dev:native libssl-dev:native

deb: $(DESTDEB)

modules:
	cd $(DEST) && make -j$(shell nproc) CC="ccache gcc" $@

$(DESTDEB): setup
	cd $(DEST) && make -j$(shell nproc) CC="ccache gcc" LOCALVERSION="-$(VERS)" KDEB_PKGVERSION="$(KVERS)-$(VERS)" EMAIL="Rob Thomas <xrobau@gmail.com>" DPKG_FLAGS=$(DPKG_FLAGS) bindeb-pkg

SCONFIG=configs/defconfig-$(KMAJOR)

$(DEST)/.config: $(DEST)/Makefile sgm-dahdi $(DEST)/arch/x86/configs/pbx_defconfig patch
	cd $(DEST) && make pbx_defconfig
	touch $(DEST)/.config

$(DEST)/arch/x86/configs/pbx_defconfig: $(SCONFIG)
	cp -p $< $@

$(DEST)/Makefile: $(ORIG)
	mkdir -p $(DEST) && \
	tar -C $(DEST) --strip-components=1 -xf $(ORIG) && \
	touch $@

patch: $(DEST)/.patched

$(DEST)/.patched: $(DEST)/.config
	@cd $(DEST); \
	for x in $(wildcard $(DIR)/patches/*.patch); do \
		echo Applying patch $$(basename $$x); \
		patch -p0 < $$x; \
	done; \
	for x in $(wildcard $(DIR)/patches/*.sh); do \
		echo Running patch script $$(basename $$x); \
		$$x -i; \
	done
	@touch $@

unpatch:
	@[ -d $(DEST) ] && cd $(DEST) && \
	for x in $(wildcard $(DIR)/patches/*.patch); do \
		echo Removing patch $$(basename $$x); \
		patch -R -N -r/dev/null -p0 < $$x || :; \
	done && \
	for x in $(wildcard $(DIR)/patches/*.sh); do \
		echo Running patch uninstall $$(basename $$x); \
		$$x -u; \
	done && \
	rm -f .patched || :


src/linux-6%.xz:
	@mkdir -p src
	@wget https://cdn.kernel.org/pub/linux/kernel/v6.x/$(@F) -O $@

src/linux-5%.xz:
	@mkdir -p src
	@wget https://cdn.kernel.org/pub/linux/kernel/v5.x/$(@F) -O $@

src/linux-firmware-%.tar.gz:
	@mkdir -p src
	wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/snapshot/$(@F) -O $@

sgm-dahdi: $(DAHDI_SRC) $(DEST)/drivers/dahdi $(DAHDI_SRC)/include/dahdi/version.h $(DEST)/include/dahdi $(DEST)/include/uapi/dahdi dmpatched

dmpatched: $(DEST)/drivers/.Makefile_patched $(DEST)/drivers/.KConf_patched

$(DEST)/drivers/.Makefile_patched:
	@sed -i -e '/linux\/dahdi/d' \
		-e '/^config_leak_ignores=/a include/uapi/dahdi/dahdi_config.h:CONFIG_HDLC' \
		-e '/^config_leak_ignores=/a include/uapi/dahdi/dahdi_config.h:CONFIG_HDLC_MODULE' \
		-e '/^config_leak_ignores=/a include/uapi/dahdi/dahdi_config.h:CONFIG_PPP' \
		-e '/^config_leak_ignores=/a include/uapi/dahdi/dahdi_config.h:CONFIG_PPP_MODULE' \
		-e '/^config_leak_ignores=/a include/uapi/dahdi/dahdi_config.h:CONFIG_DAHDI_CORE_TIMER' \
		-e '/^config_leak_ignores=/a include/uapi/dahdi/kernel.h:CONFIG_DAHDI_NET' \
		-e '/^config_leak_ignores=/a include/uapi/dahdi/kernel.h:CONFIG_DAHDI_PPP' \
		-e '/^config_leak_ignores=/a include/uapi/dahdi/kernel.h:CONFIG_DAHDI_ECHOCAN_PROCESS_TX' \
		-e '/^config_leak_ignores=/a include/uapi/dahdi/kernel.h:CONFIG_DAHDI_MIRROR' \
		-e '/^config_leak_ignores=/a include/uapi/dahdi/kernel.h:CONFIG_CALC_XLAW' \
		-e '/^config_leak_ignores=/a include/uapi/dahdi/kernel.h:CONFIG_DAHDI_WATCHDOG' \
		-e '/^config_leak_ignores=/a include/uapi/dahdi/kernel.h:CONFIG_PROC_FS' \
		-e '/^config_leak_ignores=/a include/uapi/dahdi/user.h:CONFIG_DAHDI_MIRROR' \
		$(DEST)/scripts/headers_install.sh && \
	sed -i -e '/dahdi/d' -e '/endmenu/i source "drivers/dahdi/Kconfig"' $(DEST)/drivers/Kconfig && \
	sed -i -e '/dahdi/d' $(DEST)/drivers/Makefile && \
	echo 'obj-$$(CONFIG_DAHDI)  += dahdi/' >> $(DEST)/drivers/Makefile
	touch $@

$(DAHDI_SRC):
	cd src && git clone -b sgm https://github.com/phonebocx/dahdi-linux.git

$(DAHDI_SRC)/include/dahdi/version.h:
	cd $(DAHDI_SRC) && make include/dahdi/version.h

# '---help---' is no longer the delimter for help. It's now 'help'. Fix it.
$(DEST)/drivers/.KConf_patched: $(DEST)/drivers/dahdi/xpp/.KConf_patched $(DEST)/drivers/dahdi/.KConf_patched

$(DEST)/drivers/dahdi/xpp/.KConf_patched $(DEST)/drivers/dahdi/.KConf_patched: $(DEST)/drivers/dahdi
	@sed -i 's/---help---/help/g' $(@D)/Kconfig
	@touch $@

$(DEST)/drivers/dahdi:
	rsync -av --delete  $(DAHDI_SRC)/drivers/dahdi/ $@

$(DEST)/include/dahdi $(DEST)/include/uapi/dahdi:
	mkdir -p $@ && cp $(DAHDI_SRC)/include/dahdi/*.h $@
 

