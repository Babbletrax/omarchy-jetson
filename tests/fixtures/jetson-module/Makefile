obj-m += omarchy_jetson_probe.o

.PHONY: all clean

all:
	$(MAKE) -C /usr/lib/modules/$(shell uname -r)/build M=$(CURDIR) modules

clean:
	$(MAKE) -C /usr/lib/modules/$(shell uname -r)/build M=$(CURDIR) clean
