# The base package for Vulture 4 Operating System

## Purpose

This is the root package of the Vulture4 project.

What it basically does is:
 - Harden the operating system
 - Install packages needed by Vulture
 - Install system scripts to bootstrap Vulture services and Jails
 

## Getting Vulture4 (the easy way)
How to get Vulture4 ?
 - Download it from http://hbsd.vultureproject.org/13-stable/amd64/amd64/BUILD-LATEST/

We provide hypervisor images with QCOW2, RAW, VHD(X) and VMDK formats that have all packages installed.
We also provide iso files, which currently are bare HardenedBSD installation drives (they don't contain Vulture packages).
You can also directly download base, kernel, ports and src archives containing the built version supported by Vulture.
 
 
 ## Building from scratch (the hard way)
 You want to build your own VultureOS from scratch ?
 - Follow [The Building Guide](https://github.com/VultureProject/vulture-from-scratch)


## Setup
Once you have a valid image, follow the [Initial Configuration](CONFIGURE.md)
