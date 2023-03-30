# OneAPI-ASP 

## Overview
This repository contains files necessary to generate ASP for OFS ADP cards.
The hardware currently relies on platforms that implement the OFS PCIe TLP
format using AXI-S interfaces, and the software uses OPAE SDK interfaces.

## Repo Structure

The repository is structured as follows:

* n6001: contains files specific to n6001 platform used to generate ASP for n6001 platform.
Please refer to README in n6001 directory for more details.

* d5005: contains files specific to d5005 platform used to generate ASP for d5005 platform.
Please refer to README in d5005 directory for more details.

* common: contains common software code, files shared among different board/platforms. 
The software source code that is used to compile MMD/ASP and utilities that are used by the OneAPI runtime to interface with the ASP.
It also contains common hardware design files shared among different board/platforms.
