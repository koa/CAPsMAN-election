/user group
add name=ssh-admin policy=ssh,ftp,reboot,read,write,policy,test,winbox,password,web,sniff,sensitive,api,romon,!local,!telnet,!dude,!tikapp
/ip service
set telnet disabled=yes
set ftp disabled=yes

/system script
remove import-keys
add dont-require-permissions=no owner=koa name=import-keys policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive source=":do {\
    \n\t:local keepUsers\
    \n\t:set keepUsers [/user find where name=\"admin\"]\
    \n\t:local user \"koa\"\
    \n\t\
    \n\t{\
    \n\t\t\
    \n\t\t/tool fetch url=\"https://github.com/\$user.keys\" dst-path=keys\
    \n\t\t:local keys [/file get [/file find name=keys] contents] ;\
    \n\t\t:local contentLen [:len \$keys];\
    \n\
    \n\t\t:local lineEnd 0;\
    \n\t\t:local line \"\";\
    \n\t\t:local lastEnd 0;\
    \n\
    \n\t\t:if ([:len [/user find where name=\$user]] > 0) do={\
    \n\t\t\t/user set group=full \$user\
    \n\t\t} else={\
    \n\t\t\t/user add name=\$user group=ssh-admin\
    \n\t\t}\
    \n\t\t:set keepUsers (\$keepUsers,[/user find where name=\$user])\
    \n\t\t/user ssh-keys remove [/user ssh-keys find key-owner=\$user]\
    \n\
    \n\t\t:while (\$lineEnd < \$contentLen) do={\
    \n\t\t\t:set lineEnd [:find \$keys \"\\n\" \$lastEnd];\
    \n\t\t\t# if there are no more line breaks, set this to be the last one\
    \n\t\t\t:if ([:len \$lineEnd] = 0) do={\
    \n\t\t\t\t:set lineEnd \$contentLen;\
    \n\t\t\t}\
    \n\t\t\t# get the current line based on the last line break and next one\
    \n\t\t\t:set line [:pick \$keys \$lastEnd \$lineEnd];\
    \n\t\t\t:set lastEnd (\$lineEnd + 1);\
    \n\t\t\t# don't process blank lines\
    \n\t\t\t:if (\$line != \"\\r\" && [:len \$line] >0 && \$line~\"^ssh-rsa\") do={\
    \n\t\t\t\t/file print file=key.txt\
    \n\t\t\t\t:delay 2\
    \n\t\t\t\t/file set contents=\"\$line \$user\" key.txt\
    \n\t\t\t\t:do {\
    \n\t\t\t\t\t/user ssh-keys import user=\$user public-key-file=key.txt\
    \n\t\t\t\t} on-error={ :put \"cannot import key\"};\
    \n\t\t\t}\
    \n\t\t}\
    \n\t\t:log info \"keys updated for \$user\"\
    \n\t}\
    \n\t:foreach user in=[/user find] do={\
    \n\t\t:if ([:find \$keepUsers \$user]>=0) do={} else={\
    \n\t\t\t/user remove \$user;\
    \n\t\t};\
    \n\t};\
    \n} on-error={:log error \"Cannot import keys\" }\
    \n/file remove key.txt\
    \n/file remove keys"
/system scheduler
add interval=3h name=import-keys on-event="/system script run import-keys " policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon start-time=startup
