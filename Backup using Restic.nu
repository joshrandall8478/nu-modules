#!/usr/bin/env nu

# The header is in the form of frontmatter with a "# " prefix. This blog explains how to exxtract the 
# frontmatter from a file.
# https://www.kiils.dk/en/blog/2024-09-19-inspecting-yaml-frontmatter-in-markdown-files-with-nushell/
########################################  --== Begin frontmatter ==-- ########################################
# ---
# Name: Backup using Restic
# Description: File-level backup using Restic and Rclone with Backblaze storage
# Long Description: -|
# 	Backup using Restic for backup and rclone to connect to storage backend.
# 	  - rclone: https://github.com/rclone/rclone
# 	  - restic: https://github.com/restic/restic
# 	  - Backblaze: https://www.backblaze.com/docs/cloud-storage-integrate-rclone-with-backblaze-b2
# Authors:
# 	- Joshua Randall (https://github.com/joshrandall8478)
# 	- NiceGuyIT (https://github.com/NiceGuyIT)
# Version: v0.1.0
# Hash: TBD
# Source: https://gitea.n.niceguyit.biz/NiceGuyIT/nu-modules-private/src/branch/main/scripts
# Documentation: https://d.niceguyit.biz/en/internal/how-to/add-new-company-to-backup
# ---
########################################  --== End frontmatter ==-- ########################################

########################################  --== Configuration ==-- ########################################
# The configuration is composed of 3 environment variables represeting the three sections, storage using
# the rclone connector, restic configuration and the file-level backup configuration.
#
# 1. BACKUP_STORAGE_BASE64 is the base64 encoded version of the following JSON. It is assumed an application
#    key is created with access to only the bucket mentioned.
#        print $"BACKUP_STORAGE_BASE64=(open Client-restic-UniqueCode-storage.json | to json --raw | encode base64 --url)"
#        {
#          "storage": {
#            # https://www.backblaze.com/docs/cloud-storage-integrate-rclone-with-backblaze-b2
#            "provider": "backblaze"
#            # rclone provider name: https://rclone.org/b2/
#            "type": "b2",
#            # Usually one bucket per client.
#            "bucket": "Bucket-name-from-Backblaze"
#            # Application Key specific to the bucket
#            "key_id": "keyID",
#            "application_key": "applicationKey",
#            # Endpoint is not normally needed and can be blank.
#            "endpoint": "",
#          }
#        }
# 2. BACKUP_RESTIC_BASE64 is the base64 encoded version of the following JSON.
#        print $"BACKUP_RESTIC_BASE64=(open Client-restic-UniqueCode-restic.json | to json --raw | encode base64 --url)"
#        {
#          "restic": {
#            "backend": "rclone",
#            "password": "Randomly-generated-password"
#          }
#        }
# 3. BACKUP_CONFIG_BASE64 is the base64 encoded version of the following JSON.
#        print $"BACKUP_CONFIG_BASE64=(open Client-restic-UniqueCode-config.json | to json --raw | encode base64 --url)"
#        {
#          "backup": {
#            "files": {
#              "glob_list": [
#                "/srv/d1/data/*"
#              ]
#            }
#          }
#        }
#
# Restic uses the "rclone" backend, a provider and a bucket. The "rclone" backend is static. The "RCLONE_PROVIDER" is
# static because it is provided as environment variables to rclone. The PROVIDER_BUCKET_NAME is provided in the storage
# configuration above.
#     rclone:RCLONE_PROVIDER:PROVIDER_BUCKET_NAME
#
########################################  --== Configuration ==-- ########################################

# Run this script as a user
def "runas user" [
    user: string        # User to run this script
]: nothing -> nothing {
	if (is-admin) {
		# Run this script as the user.
		log info $"Running the current script as user"
		log info $"script path: '($env.CURRENT_FILE)'"
		log info $"user: '($env.JUST_RUNAS_USER)'"
		try {
			let user_id = (^id --user $env.JUST_RUNAS_USER)
		} catch {
			log error $"User does not exist: '($env.JUST_RUNAS_USER)'"
			return
		}
		let sudo_args = [
			'--user' $env.JUST_RUNAS_USER
			'--preserve-env=PRIVATE_SSH_KEY_BASE64,PRIVATE_SSH_KEY_NAME,JUST_APP_DIR'
		]
        # Adjust the file permissions so the user can read it.
        # Note: Execute permission is not needed because it's being called as an argument to nu
        chmod go+r $env.CURRENT_FILE
		^sudo ...$sudo_args /usr/local/bin/nu $env.CURRENT_FILE
		return
	}
}

def "backup help" []: nothing -> nothing {
    ^$nu.current-exe $env.CURRENT_FILE --help
}

# List all snapshots in the repository
def "backup list" [
    repo: string        # repository name
]: nothing -> any {
    use std log
	log info $"Listing backup snapshots in repository '($repo)'"
	^restic snapshots --repo $repo
}

# Run the backup to create a new snapshot
def "backup run" [
    repo: string        # repository name
]: any -> nothing {
    let input = $in
    $input
    | get files.glob_list
    | each {|it|
        glob $it | each {|dir|
            use std log
            log info $"Backing up files to repository '($repo)' in directory: ($dir)"
            ^restic backup --repo $repo $dir --json | from json
        }
    }
}

# Restore a snapshot to a target directory
def "backup restore" [
    repo: string        # repository name
    snapshot: string,
    target: string
]: [] {
    use std log
	log info $"Restoring files from '($repo)'"
	^restic restore --repo $repo --target $"($target)" $snapshot
}

# Initialize a new Restic repository.
def "backup init" [
    repo: string        # repository name
]: nothing -> any {
    use std log
	log info $"Initializing restic repository at '($repo)'"
	^restic init --repo $repo
}

# Main module to run the backup, list snapshots.
export def main [
    command: string         # Command to run
]: nothing -> any {
    use std log
	#requires $env.ENCODED_CONFIG_BASE64
    # For some reason, in tacticalRMM, base64 is output as a string. We can then just turn this
    # into json.
    # See the documenetation above for the command to convert a JSON file to a base64 encoded string.

    # Nu 0.101.0 installed in /usr/local/bin/ on the servers:
	#let config = ($env.BACKUP_CONFIG_BASE64 | decode base64 --url | decode utf-8 | from json)
    # Nu 0.91.0 used by Tactical.
	let config = {
        backup: ($env.BACKUP_CONFIG_BASE64 | decode base64 | from json | get backup)
	    restic: ($env.BACKUP_RESTIC_BASE64 | decode base64 | from json | get restic)
	    storage: ($env.BACKUP_STORAGE_BASE64 | decode base64 | from json | get storage)
    }

    # https://restic.readthedocs.io/en/stable/040_backup.html#environment-variables
	$env.RESTIC_PASSWORD = $config.restic.password

    # The Restic backend is made up "rclone", the provider name (static) and the provider bucket name (dynamic).
    let repo = (['rclone', 'b2remote', $config.storage.bucket] | str join ':')

    # https://rclone.org/docs/#environment-variables
	$env.RCLONE_CONFIG_B2REMOTE_TYPE = $config.storage.type
	$env.RCLONE_CONFIG_B2REMOTE_ACCOUNT = $config.storage.key_id
	$env.RCLONE_CONFIG_B2REMOTE_KEY = $config.storage.application_key
	#$env.RCLONE_CONFIG_B2REMOTE_ENDPOINT = $config.storage.endpoint

    # Verbose logging for rclone, used for debugging.
    #$env.RCLONE_VERBOSE = 2

    let command = ($command | default ($env.BACKUP_COMMAND? | default "help"))
    log info $"command: ($command)"
    # The output should be captured.
    # https://restic.readthedocs.io/en/stable/075_scripting.html
	match $command {
		"list" => {
            backup list $repo
        }
		"run" => {
            $config.backup | backup run $repo
        }
        "print" => {
            $env.RESTIC_DIR
        }
        "init" => {
            backup init $repo
        }
        _ => {
            backup help
        }
	}
}
