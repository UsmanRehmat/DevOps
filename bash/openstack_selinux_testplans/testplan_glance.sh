#!/bin/bash

# The purpose of this test is to prove that a OpenStack glance processes are protected by SELinux
# policies.
# This purpose is achieved by proving that glance processes, running in their own SELinux domain,
# can not execute a file (script) even if the file is executable by DAC policy rules.

# Glance executable/binary files are assigned different SELinux labels:
ls -Z /bin/ | grep glance
#
#	-rwxr-xr-x. root root   unconfined_u:object_r:bin_t:s0   glance
#	-rwxr-xr-x. root root   unconfined_u:object_r:glance_api_exec_t:s0 glance-api
#	-rwxr-xr-x. root root   unconfined_u:object_r:bin_t:s0   glance-artifacts
#	-rwxr-xr-x. root root   unconfined_u:object_r:bin_t:s0   glance-cache-cleaner
#	-rwxr-xr-x. root root   unconfined_u:object_r:bin_t:s0   glance-cache-manage
#	-rwxr-xr-x. root root   unconfined_u:object_r:bin_t:s0   glance-cache-prefetcher
#	-rwxr-xr-x. root root   unconfined_u:object_r:bin_t:s0   glance-cache-pruner
#	-rwxr-xr-x. root root   unconfined_u:object_r:bin_t:s0   glance-control
#	-rwxr-xr-x. root root   unconfined_u:object_r:bin_t:s0   glance-manage
#	-rwxr-xr-x. root root   unconfined_u:object_r:glance_registry_exec_t:s0 glance-registry
#	-rwxr-xr-x. root root   unconfined_u:object_r:bin_t:s0   glance-replicator
#	-rwxr-xr-x. root root   unconfined_u:object_r:glance_scrubber_exec_t:s0 glance-scrubber
#
# The binary file glance-api is labelled with glance_api_exec_t SELinux type which when executed
# spawns a process in glance_api_t SELinux domain.
# glance-registry is labelled with glance_registry_exec_t SELinux type, when executed triggers
# a process in glance_registry_t SELinux domain.
# Similarly glance-scrubber is labelled with glance_scrubber_exec_t SELinux type and when executed
# spawns a process in glance_scrubber_t SELinux domain.
# Whereas other files are assigned bin_t label.

# In this test plan, we are going to test all of these SELinux labels related to glance service.
# To let glance processes do what we want, we have to originate our own processes with SELinux
# labels glance_api_t, glance_registry_t and glance_scrubber_t. In order to spawn glance processes
# in their respective SELinux domains we need executable files with glance_api_exec_t,
# glance_registry_exec_t and glance_scrubber_exec_t SELinux types respectively. Using these
# executable files, we can try some malicious activities like executing another harmful script
# placed in the system.

# Create two files 'glance_test.sh' and 'random_script.sh' in a directory inside root.
# glance_test.sh file will be used to spawn processes with any desired SELinux label and 
# random_script.sh file is a random bash script that will be accessed by the processes originated
# from glance_test.sh file. The bash script 'random_script.sh' can be any linux bash script.
touch glance_test.sh
touch random_script.sh

# Make sure SELinux context of both files is system_u:object_r:admin_home_t:s0
ls -Z
# The expected output of this command is a list of file with SELinux context, as below
#	-rwxr-xr-x. root root unconfined_u:object_r:admin_home_t:s0 random_script.sh
#	-rwxr-xr-x. root root unconfined_u:object_r:admin_home_t:s0 glance_test.sh

# Write some harmful bash commands in random_script.sh file.
cat > random_script.sh << _EOF
#!/bin/sh
id -Z
setenforce 0
echo SELinux status is set to: \$(getenforce)
setenforce 1
echo SELinux status is set to: \$(getenforce)
_EOF

# In file glance_test.sh file, run the random_script.sh script.
cat > glance_test.sh << _EOF
#!/bin/sh
./random_script.sh
_EOF

# Make sure both files are executable by DAC rules
chmod +x random_script.sh
chmod +x glance_test.sh
# These commands will change the mode of glance_test.sh and random_script.sh file to executable.

# Run glance_test.sh and see if it displays the below output 
#	unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023
#	SELinux status is set to: Permissive
#	SELinux status is set to: Enforcing

# Execute the script using 'runcon' with system_u:system_r:initrc_t:s0 SELinux context because this
# command will execute the script in initrc_t domain. And initrc_t domain is allowed to transition
# to any other domain
runcon system_u:system_r:initrc_t:s0 sh -c ./glance_test.sh | cat
# This command is just a test of environment that everything is working fine because this command
# is supposed to work without any issue.
# When command is executed successfully, you will see the following output,
#	system_u:system_r:initrc_t:s0
#	SELinux status is set to: Permissive
#	SELinux status is set to: Enforcing

# Current SELinux context of glance_test.sh is unconfined_u:object_r:admin_home_t:s0, we need to
# change this context to one of glance binary context to see if glance processes are protected or
# not.

#****************************************glance-api test******************************************#
# First test:
# First change the context of glance_test.sh to unconfined_u:object_r:glance_api_exec_t:s0, same
# as that of glance-api binary file, so that it can spawn a process in glance_api_t SELinux domain.
chcon -t glance_api_exec_t glance_test.sh
# Make sure this command works fine without any error.

# Since glance_test.sh is of glance_api_exec_t SELinux type which when executed will originates a
# process with glance_api_t SELinux domain. This command make sure that glance_test.sh is executed
# in the specified context. The bash file glance_test.sh is executed in initrc_t domain because
# initrc_t domain can transition to any other domain. So this execution will originates a process
# with glance_api_t domain.
runcon system_u:system_r:initrc_t:s0 sh -c ./glance_test.sh | cat
# The command is expected to fail and failure  will be logged in that file /var/log/audit/audit.log
# Look for an entry of following type:
#
#	type=AVC msg=audit(1466452577.462:657148): avc:  denied  { execute } for  pid=15582 comm=
#	"glance_test.sh" name="random_script.sh" dev="sda2" ino=7566524546 scontext=
#	system_u:system_r:glance_api_t:s0 tcontext=unconfined_u:object_r:admin_home_t:s0 tclass=file
#
# This log entry shows that comm="glance_test.sh" is denied to execute file name="random_script.sh".
# The source context, which is actually the context of the process, 
# "scontext=system_u:system_r:glance_api_t:s0" is denied to access target context
# "tcontext=unconfined_u:object_r:admin_home_t:s0" for "execute" permission.
# So what happened is, when we execute glance_test.sh with SELinux type glance_api_exec_t, it
# generates a process with context "system_u:system_r:glance_api_t:s0". As we scripted this process
# to execute a bash script "random_script.sh" which has the context 
# "unconfined_u:object_r:admin_home_t:s0". Since glance_api_t process is not allowed to execute this
# script by the SELinux policy so it fails with this log error.
 
# Second test:
# A process with SELinux domain glance_api_t can execute file with SELinux type glance_api_exec_t
# because the binary files in /bin directory are label with type glance_api_exec_t.
# In order to prove that process running in glance_api_t domain can execute the glance_api_exec_t
# type files, change the SELinux type of random_script.sh script to glance_api_exec_t and then run
# the glance_test.sh script again.
chcon -t glance_api_exec_t random_script.sh
runcon system_u:system_r:initrc_t:s0 sh -c ./glance_test.sh | cat
# When command is executed successfully, you see the following output
#	system_u:system_r:glance_api_t:s0
#	SELinux status is set to:
#	SELinux status is set to:
# Now glance api process is able to execute the bash script of glance_api_exec_t type but still it
# is not able to change SELinux mode because the process is running in glance_api_t domain which
# don't have permission to change SELinux status.

# Restore the context before you go for the next test.
# Reset the context of glance_test.sh and random_script.sh file to orignal state that was 
# unconfined_u:object_r:admin_home_t:s0. Use commands below to reset context,
restorecon glance_test.sh
restorecon random_script.sh
# Make sure these commands executed successfully, the expected output for both command is;
#	Full path required for exclude: net:[4026534107].
#	Full path required for exclude: net:[4026534107].
#	Full path required for exclude: net:[4026534213].
#	Full path required for exclude: net:[4026534213].

#*************************************glance-registry test****************************************#
# First test:
# For glance-registry change the context of glance_test.sh file to
# unconfined_u:object_r:glance_registry_exec_t:s0, same as that of glance-registry binary file, so
# that it can spawn a process in glance_registry_t SELinux domain.
chcon -t glance_registry_exec_t glance_test.sh
# Make sure this command works fine without any error.

# Since glance_test.sh is of glance_registry_exec_t SELinux type which when executed will
# originates a process with glance_registry_t SELinux domain. This command make sure that
# glance_test.sh is executed in the specified context. The bash file glance_test.sh is executed in
# initrc_t domain because initrc_t domain can transition to any other domain. So this execution
# will originates a process with glance_registry_t domain.
runcon system_u:system_r:initrc_t:s0 sh -c ./glance_test.sh | cat
# The command is expected to fail and failure  will be logged in that file /var/log/audit/audit.log
# Look for an entry of following type
#
#	type=AVC msg=audit(1466459928.039:665650): avc:  denied  { execute } for  pid=13668 comm=
#	"glance_test.sh" name="random_script.sh" dev="sda2" ino=7566524546 scontext=
#	system_u:system_r:glance_registry_t:s0 tcontext=unconfined_u:object_r:admin_home_t:s0 tclass=file
#
# This log entry shows that comm="glance_test.sh" is denied to execute file name="random_script.sh"
# The source context, which is actually the context of the process, 
# "scontext=system_u:system_r:glance_registry_t:s0" is denied to access target context
# "tcontext=unconfined_u:object_r:admin_home_t:s0" for "execute" permission.
# So what happened is, when we execute glance_test.sh with SELinux type glance_registry_exec_t, it
# generates a process with context "system_u:system_r:glance_registry_t:s0". As we scripted this
# process to execute a bash script "random_script.sh" which has the context 
# "unconfined_u:object_r:admin_home_t:s0". Since glance_registry_t process is not allowed to
# execute this script by the SELinux policy so it fails with this log error.
 
# Second test:
# A process with SELinux domain glance_registry_t can execute file with SELinux type 
# glance_registry_exec_t because the binary file in /bin/glance-registry directory is label with
# type glance_registry_exec_t. In order to prove that process running in glance_registry_t domain
# can execute the glance_registry_exec_t type files, change the SELinux type of random_script.sh
# script to glance_registry_exec_t and then run the glance_test.sh script again.
chcon -t glance_registry_exec_t random_script.sh
runcon system_u:system_r:initrc_t:s0 sh -c ./glance_test.sh | cat
# When command is executed successfully, you see the following output
#	system_u:system_r:glance_registry_t:s0
#	SELinux status is set to:
#	SELinux status is set to:
# Now glance-registry process is able to execute the bash script of glance_registry_exec_t type
# but still it is not able to change SELinux mode because the process is running in 
# glance_registry_t domain which don't have permission to change SELinux status.

# Restore the context before you go for the next test.
# Reset the context of glance_test.sh and random_script.sh file to orignal state that was 
# unconfined_u:object_r:admin_home_t:s0. Use commands below to reset context,
restorecon glance_test.sh
restorecon random_script.sh
# Make sure these commands executed successfully, the expected output for both command is;
#	Full path required for exclude: net:[4026534107].
#	Full path required for exclude: net:[4026534107].
#	Full path required for exclude: net:[4026534213].
#	Full path required for exclude: net:[4026534213].

#*************************************glance-scrubber test****************************************#
# First test:
# Now change the context of glance_test.sh to unconfined_u:object_r:glance_scrubber_exec_t:s0, same
# as that of glance-scrubber binary file, so that it can spawn a process in glance_scrubber_t
# SELinux domain.
chcon -t glance_scrubber_exec_t glance_test.sh
# Make sure this command works fine without any error.

# Since glance_test.sh is of glance_scrubber_exec_t SELinux type which when executed will
# originates a process with glance_scrubber_t SELinux domain. This command make sure that
# glance_test.sh is executed in the specified context. The bash file glance_test.sh is executed in
# initrc_t domain because initrc_t domain can transition to any other domain. So this execution
# will originates a process with glance_scrubber_t domain.
runcon system_u:system_r:initrc_t:s0 sh -c ./glance_test.sh | cat
# The command is expected to fail and failure  will be logged in that file /var/log/audit/audit.log
# Look for an entry of following type
#
#	type=AVC msg=audit(1466460423.819:666236): avc:  denied  { execute } for  pid=43322 comm=
#	"glance_test.sh" name="random_script.sh" dev="sda2" ino=7566524546 scontext=
#	system_u:system_r:glance_scrubber_t:s0 tcontext=unconfined_u:object_r:admin_home_t:s0 tclass=file
#
# This log entry shows that comm="glance_test.sh" is denied to execute file name="random_script.sh"
# The source context, which is actually the context of the process, 
# "scontext=system_u:system_r:glance_scrubber_t:s0" is denied to access target context
# "tcontext=unconfined_u:object_r:admin_home_t:s0" for "execute" permission.
# So what happened is, when we execute glance_test.sh with SELinux type glance_scrubber_exec_t, it
# generates a process with context "system_u:system_r:glance_scrubber_t:s0". As we scripted this
# process to execute a bash script "random_script.sh" which has the context 
# "unconfined_u:object_r:admin_home_t:s0". Since glance_scrubber_t process is not allowed to
# execute this script by the SELinux policy so it fails with this log error.

# Second test:
# A process with SELinux domain glance_scrubber_t can execute file with SELinux type
# glance_scrubber_exec_t because the binary file in /bin/glance-scrubber directory is label with
# type glance_scrubber_exec_t. In order to prove that process running in glance_scrubber_t domain
# can execute the glance_scrubber_exec_t type files, change the SELinux type of random_script.sh
# script to glance_scrubber_exec_t and then run the glance_test.sh script again.
chcon -t glance_scrubber_exec_t random_script.sh
runcon system_u:system_r:initrc_t:s0 sh -c ./glance_test.sh | cat
# When command is executed successfully, you see the following output
#	system_u:system_r:glance_scrubber_t:s0
#	SELinux status is set to:
#	SELinux status is set to:
# Now glance-scrubber process is able to execute the bash script of glance_scrubber_exec_t type but
# still it is not able to change SELinux mode because the process is running in glance_scrubber_t
# domain which don't have permission to change SELinux status.

# Restore the context before you go for the next test.
# Reset the context of glance_test.sh and random_script.sh file to orignal state that was 
# unconfined_u:object_r:admin_home_t:s0. Use commands below to reset context,
restorecon glance_test.sh
restorecon random_script.sh
# Make sure these commands executed successfully, the expected output for both command is;
#	Full path required for exclude: net:[4026534107].
#	Full path required for exclude: net:[4026534107].
#	Full path required for exclude: net:[4026534213].
#	Full path required for exclude: net:[4026534213].
