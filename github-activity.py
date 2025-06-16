#!/usr/bin/env python3
"""
A simple script for generating activity summary for a set of GitHub
repositories.

## Installation and Setup

 1. Create and activate virtual environment for required packages:

        virtualenv --prompt scripts .venv
        . .venv/bin/activate

 2. Install PyGithub:

        pip3 install PyGithub

 3. Generate GitHub "personal access tokens" - to do so go to...

        https://github.com/settings/tokens

    ...and create one. It only needs "repo" permissions
    (or even "public_repo").

    github-activity.py expects access token in GITHUB_TOKEN environment
    variable.

## Example

Print activity summary for all repositories owned by user
"johndoe" and also on repository "coolstuff" owned by "janedoe"
for the past month (ending with today):

    export GITHUB_TOKEN=ghp_ABCD....
    github-sync.py --output /srv/backups/github.com \
        --user johndoe \
        --repo janedoe/coolstuff
"""

from os import environ
from datetime import date, time, datetime
import logging
import argparse
from itertools import chain
from github import Github, PullRequest

logging.basicConfig(format="%(levelname)s: %(message)s", level=logging.INFO)
log = logging.getLogger(__file__)

def debug():
    try:
        import ipdb
        ipdb.set_trace()
    except:
        breakpoint()


CREATED = 'CREATED'
UPDATED = 'UPDATED'
CLOSED = 'CLOSED'
MERGED = 'MERGED'

FMT_DEFAULT="  * {activity:<7} #{issue.number:<4} {issue.title}\n                  {issue.html_url}\n"
FMT_ONELINE="  * #{issue.number:<4} {issue.title}"


def activity_of(item, start, end):
    created = item.created_at.date()
    modified = item.last_modified_datetime.date() if item.last_modified_datetime is not None else created

    if (modified < start) or (modified > end):
        # There was no activity on given item, return
        return None
    
    if (item.state == 'closed'):
        try:
            pull = item.as_pull_request()
        except: 
            pull = None
        
        if pull is not None and pull.merged:
            return MERGED
        else:
            return CLOSED
        
    if (created >= start):
        return CREATED
    
    return UPDATED

def process(repo, startDate, endDate, format):
    items = []    
    for issue in repo.get_issues(state='all',since=datetime.combine(startDate, time())):
        activity = activity_of(issue, startDate, endDate)
        if activity is not None:
            items.append( (activity, issue) )

    items.sort(key=lambda item : item[1].number)

    if len(items) > 0:
        print("Repository %s \n" % repo.html_url)    
        for item in items:
            print(format.format(activity=item[0], issue=item[1]))
        print("")
    return True
    

if __name__ == '__main__':
    today = date.today()
    monthago = date(today.year if today.month > 1 else today.year - 1,
                    today.month if today.month > 1 else 12,
                    today.day)

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user", metavar="USER",
                        dest='users', action='append',
                        help="GitHub user/organization name include in activity summary")
    parser.add_argument("--repo", metavar="REPOSITORY",
                        dest='repos', action='append',
                        help="GitHub repository name to include in activity summary")
    parser.add_argument("--from", metavar="START_DATE",
                        dest='start',type=date.fromisoformat,
                        default=monthago,
                        help="Start of activity summary period as YYYY-MM-DD. Defaults to a month ago from today.")
    parser.add_argument("--to", metavar="END_DATE",
                        dest='end',type=date.fromisoformat,
                        default=monthago,
                        help="End of activity summary period as YYYY-MM-DD. Defaults to today.")
    parser.add_argument("--format", metavar="FORMAT",
                        dest='format',
                        default=FMT_DEFAULT,
                        help="Format to use for activities. Defaults to '%s'." % FMT_DEFAULT)
    parser.add_argument("--oneline",
                        dest='format',action='store_const',
                        const=FMT_ONELINE,
                        help="Use short one-line format for activities.")
    
    
    options = parser.parse_args()

    if (not 'GITHUB_TOKEN' in environ):
        log.error('GITHUB_TOKEN environment not found!')
        exit(1)

    if options.repos == None:
        options.repos = []

    if options.users == None:
        options.users = []

    if len(options.repos) + len(options.users) == 0:
        log.error("No --repo or --user options specified")
        exit(1)

    try:
        gh = Github(environ['GITHUB_TOKEN'])

        for login in options.users:
            user = gh.get_user(login)
            for repo in user.get_repos():
                options.repos.append(repo.full_name)

        print("TBW: Cover letter.\n\n")
        print("---\n")
        print("From %s to %s" % ( options.start, options.end) )

        all_succeeded = True
        for repo in options.repos:

            all_succeeded = all_succeeded and process(gh.get_repo(repo), options.start, options.end, options.format)

        if not all_succeeded:
            log.error("Failed to process one or more repositories")
            exit(1)
    except Exception as e:
        log.error("Exception: %s" % str(e))
        exit(1)
