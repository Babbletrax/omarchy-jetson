// SPDX-License-Identifier: GPL-2.0-only
#include <linux/init.h>
#include <linux/module.h>

static int __init omarchy_jetson_probe_init(void)
{
	pr_info("omarchy-jetson header probe loaded\n");
	return 0;
}

static void __exit omarchy_jetson_probe_exit(void)
{
	pr_info("omarchy-jetson header probe unloaded\n");
}

module_init(omarchy_jetson_probe_init);
module_exit(omarchy_jetson_probe_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Build-only probe for Omarchy Jetson kernel headers");
