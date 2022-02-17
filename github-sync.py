#!/usr/bin/env python3
"""
A simple script for uni-directional synchronization of GitHub
repositories to local mirrors.

## Installation and Setup

 1. Install PyGithub:

        pip3 install PyGithub

 2. Copy this script somewhere accessible, say /usr/local/bin

 3. Generate GitHub "personal access tokens" - to do so go to...

        https://github.com/settings/tokens

    ...and create one. It only needs "repo" permissions
    (or even "public_repo").

    github-sync.py expects access token in GITHUB_TOKEN environment
    variable.

## Example

Mirror all repositories of GitHub user 'johndoe' and
repository 'janedoe/coolstuff' to local directory
/srv/backups/github.com:

    export GITHUB_TOKEN=ghp_ABCD....
    github-sync.py --output /srv/backups/github.com \
        --user johndoe \
        --repo janedoe/coolstuff
"""

from os import environ, system as shell
from os.path import join, exists, isdir
import logging

logging.basicConfig(format="%(levelname)s: %(message)s", level=logging.INFO)
log = logging.getLogger(__file__)

def debug():
    try:
        import ipdb
        ipdb.set_trace()
    except:
        breakpoint()

def sync_repo(repo, directory):
    repo_dir = join(directory, repo.full_name)
    status = 0
    log.info("Synchronizing %s into %s" % ( repo.clone_url, repo_dir))
    if exists(repo_dir):
        status = shell('git -C %s fetch --all' % ( repo_dir ) )
    else:
        status = shell('git clone --mirror %s %s' % ( repo.clone_url , repo_dir ) )
    if status != 0:
        log.error("Failed to synchronize repository %s" % repo.clone_url)
        return False
    else:
        return True

if __name__ == '__main__':
    import argparse
    import sys
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", metavar="DIRECTORY",
                        dest='output', default='.',
                        help="directory where to save / update repositories")
    parser.add_argument("--user", metavar="USER",
                        dest='users', action='append',
                        help="GitHub user/organization name to synchronize")
    parser.add_argument("--repo", metavar="REPOSITORY",
                        dest='repos', action='append',
                        help="GitHub repository name to synchronize")
    options = parser.parse_args()

    if (not 'GITHUB_TOKEN' in environ):
        log.error('GITHUB_TOKEN environment not found!')
        exit(1)

    try:
        from github import Github
    except ImportError as e:
        log.error("Failed to import Github module. You may want to do 'pip install PyGithub'")
        exit(1)

    if options.repos == None:
        options.repos = []

    if options.users == None:
        options.users = []

    if len(options.repos) + len(options.users) == 0:
        log.error("No --repo or --user options specified")
        exit(1)

    if not exists(options.output):
        log.error("Output directory does not exist: %s" % options.output)
        exit(1)

    if not isdir(options.output):
        log.error("Output directory is not a directory: %s" % options.output)
        exit(1)

    try:
        gh = Github(environ['GITHUB_TOKEN'])

        for login in options.users:
            user = gh.get_user(login)
            for repo in user.get_repos():
                options.repos.append(repo.full_name)

        all_succeeded = True
        for repo in options.repos:
            all_succeeded = all_succeeded and sync_repo(gh.get_repo(repo), options.output)

        if not all_succeeded:
            log.error("One or more repositories failed to synchronize (see errors above)")
            exit(1)
    except Exception as e:
        log.error("Exception: %s" % str(e))
        exit(1)
