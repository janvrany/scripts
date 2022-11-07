#!/usr/bin/env python3
"""
Helper script to get OAuth2 access token (for example, to access
email on Office365).

Currently, only Microsoft Office365 is supported (other provideds,
such a Google may be added in a future if needed).


### Installation

 1. Create and activate virtual environment for required packages:

        virtualenv --prompt scripts .venv
        . .venv/bin/activate

 2. Install `msal`:

        pip3 install msal


"""


#
# General debugging support.
#
# See https://stackoverflow.com/a/242531
#

import os
import os.path
import sys

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
    import msal
except ImportError:
    logging.error("Failed to import `msal`, please `pip3 install msal`")
    sys.exit(1)



class MicrosoftO365(object):
    def __init__(self, config):
        self.config = config
        if not 'client_id' in config:
            raise ValueError("No 'client_id' in config!")
        elif not 'scopes' in config:
            raise ValueError("No 'scope' in config!")

        if 'cache' in self.config:
            self._cache = msal.SerializableTokenCache()
            if os.path.exists(config['cache']):
                self._cache.deserialize(open(config['cache'], "r").read())
        else:
            self._cache = None

        self._app = msal.ConfidentialClientApplication(
                            client_id = config.get('client_id'),
                            client_credential = config.get('client_credential', None),
                            token_cache = self._cache)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self._cache and self._cache.has_state_changed:
            with open(config['cache'], "w") as cache_file:
                cache_file.write(self._cache.serialize())

    def get_token(self, interactive = False):
        """
        Fetch and return access token as string.

        If interactive is `False` and token cache is either not
        configured or suitable refresh token is not there,
        raise an exception.

        If interactive is `True`, guide user through the
        authentication/authorization process.
        """

        reply = self._app.acquire_token_silent(config["scopes"], account=None)
        if not reply:
            # Extract the refresh token manually, sigh
            refresh_tokens = self._cache.find('RefreshToken')
            if len(refresh_tokens) > 0:
                refresh_token = refresh_tokens[0]['secret']
                reply = self._app.acquire_token_by_refresh_token(refresh_token=refresh_token, scopes=config["scopes"])
                if reply and "error" in reply:
                    raise Exception(reply["error_description"])
        if not reply:
            if interactive:
                auth_request = self._app.initiate_auth_code_flow(scopes = config.get('scopes'), redirect_uri = config.get('redirect_uri', "https://login.microsoftonline.com/common/oauth2/nativeclient"))
                auth_uri = auth_request['auth_uri']
                print(f"""
Please open folowing URL in a browser...

    {auth_uri}

...and follow instructions. Once done, it will lead you to an empty page.
Once there, please copy and paste the complete URL of that page from browser
address bar here (and press enter):""")

                auth_response = {}
                for key_and_value in input().split('?')[1].split('&'):
                    key, value = key_and_value.split('=')
                    auth_response[key] = value

                reply = self._app.acquire_token_by_auth_code_flow(auth_code_flow=auth_request, auth_response=auth_response, scopes = config.get('scopes'))
                if "error" in reply:
                    raise Exception(reply["error_description"])
            else:
                raise Exception('Cannot fetch access token: cache missing and not interactive')
        if not 'access_token' in reply:
            raise Exception('Oops, no access token in reply!')
        return reply['access_token']

    def get_username(self):
        accounts = self._app.get_accounts()
        if len(accounts) > 0:
            return accounts[0]['username']
        else:
            raise Exception("No accounts available, call 'get_token' first!")


if __name__ == '__main__':
    import argparse
    import sys
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-o", "--output", metavar="FILE",
                        dest='output', default='-',
                        help="Where to write access token, defaults to - (stdout)")
    parser.add_argument("--client", metavar="CLIENT_ID",
                        dest='client_id', default='20460e5d-ce91-49af-a3a5-70b6be7486d1',
                        help="Client (application) ID, defaults to 'GNOME Evolution` (20460e5d-ce91-49af-a3a5-70b6be7486d1)")
    parser.add_argument("--secret", metavar="CLIENT_SECRET",
                        dest='client_credential', default=None,
                        help="Client (application) secret, defaults to none")
    parser.add_argument("--scope", metavar="SCOPE",
                        dest='scopes', action='append',
                        help="Authorization scope, defaults to 'https://outlook.office.com/IMAP.AccessAsUser.All'")
    parser.add_argument("--cache", metavar="CACHE",
                        dest='cache', default=None,
                        help="Path to token cache file")
    parser.add_argument("--debug",
                        action="store_const", const=True, default=False,
                        help="Enable debugging")
    parser.add_argument("--test-imap",
                        dest='test_imap', action="store_const", const=True, default=False,
                        help="Enable debugging")


    options = parser.parse_args()

    if options.debug:
        sys.excepthook = excepthook
        sys.breakpointhook = breakpointhook

    config = {
        'client_id' : options.client_id,
        'client_credential' : options.client_credential,
        'scopes' : options.scopes if options.scopes else ["https://outlook.office.com/IMAP.AccessAsUser.All"],
        'cache' : options.cache
    }

    with MicrosoftO365(config) as provider:
        try:
            access_token = provider.get_token(sys.stdout.isatty())
            if options.test_imap:
                username = provider.get_username()

                import imaplib
                with imaplib.IMAP4_SSL('outlook.office365.com') as imap:
                    imap.debug = 4
                    imap.authenticate('XOAUTH2', lambda x : f"user={username}\x01auth=Bearer {access_token}\x01\x01")
                    imap.select('inbox')
            else:
                if options.output == '-':
                    print(access_token)
                else:
                    with open(options.output, 'w') as output:
                        output.write(access_token)
        except KeyboardInterrupt:
            pass
        except Exception as e:
            if options.debug:
                raise e
            else:
                logging.error(str(e))
