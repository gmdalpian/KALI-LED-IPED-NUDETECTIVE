#!/bin/bash
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 1
sudo update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.9/bin/python3.9 2
sudo update-alternatives --set python3 /usr/local/bin/python3.9/bin/python3.9
