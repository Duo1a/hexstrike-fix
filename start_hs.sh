#!/bin/bash
cd /home/duola/Desktop/Hexstrike-AI-master
export PATH="/home/duola/.local/bin:/home/duola/go/bin:/home/duola/.gem/ruby/3.3.0/bin:$PATH"
exec setsid nohup python3 hexstrike_server.py > /home/duola/hexstrike.log 2>&1 < /dev/null &
