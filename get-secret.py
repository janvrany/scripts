#!/usr/bin/env python3
"""
Helper script to get "secret" (password) from "secrets storage".
If you need OAUTH2 token, use "get-oauth2-token.py" script.

### Installation

 1. Create and activate virtual environment for required packages:

        virtualenv --prompt scripts .venv
        . .venv/bin/activate

 2. Install `secretstorage`:

        pip3 install secretstorage

Alternatively:

    apt-get install python3-secretstorage

"""

#
# General debugging support.
#
# See https://stackoverflow.com/a/242531
#

import os
import os.path
import sys
import json

try:
    import ipdb

    debugger = ipdb
except ImportError:
    import pdb
    debugger = pdb


def excepthook(type, value, tb):
    if hasattr(sys, "ps1") or not sys.stderr.isatty():
        # we are in interactive mode or we don't have a tty-like
        # device, so we call the default hook
        sys.__excepthook__(type, value, tb)
    else:
        # we are NOT in interactive mode, print the exception...
        import traceback
        traceback.print_exception(type, value, tb)
        # ...then start the debugger in post-mortem mode.
        debugger.post_mortem(tb)


def breakpointhook(*args, **kws):
    if os.getenv("PYTHONBREAKPOINT") is not None:
        # Use specified her own preferred debugger, defer to
        # default handling.
        sys.__breakpointhook__(*args, **kws)
    else:
        print("breakpoint() hit!")
        debugger.set_trace()

import logging
logging.basicConfig(format="%(levelname)s: %(message)s", level=logging.INFO)
log = logging.getLogger(__file__)


try:
    import secretstorage
except ImportError:
    logging.error("Failed to import `secretstorage`, please `pip3 install secretstorage`")
    sys.exit(1)



def get_secret(secret_title):
    """
    Fetch and return secret (password) labelled secret_title from default
    secret storage.
    """
    secrets = secretstorage.get_default_collection(secretstorage.dbus_init())
    for secret in secrets.search_items({ 'Title' : secret_title }):
        return secret.get_secret().decode('utf8')
    raise Exception("No such secret: %s" % secret_title)

if __name__ == '__main__':
    import argparse
    import sys
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-o", "--output", metavar="FILE",
                        dest='output', default='-',
                        help="Where to write secret, defaults to - (stdout)")
    parser.add_argument("--name",
                        dest='secret', default=None,
                        help="Name (title) of secret service entry containing the refresh token. Either --secret or --cache is allowed, not both.")
    parser.add_argument("--debug",
                        action="store_const", const=True, default=False,
                        help="Enable debugging")

    options = parser.parse_args()

    if options.debug:
        sys.excepthook = excepthook
        sys.breakpointhook = breakpointhook

    try:
        if options.secret is None:
            raise Exception("Secret name not specified (missing --name option?)")

        secret = get_secret(options.secret)
        if options.output == '-':
            print(secret)
        else:
            with open(options.output, 'w') as output:
                output.write(secret)
    except Exception as e:
        if options.debug:
            raise e
        else:
            logging.error(str(e))
        sys.exit(1)
    sys.exit(0)
