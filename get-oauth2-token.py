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

 2. Install `msal` and `secretstorage`:

        pip3 install msal secretstorage

Alternatively:

    apt-get install python3-msal python3-secretstorage

"""

#
# Defaults
#
DEFAULT_OAUTH2_CLIENT_ID='20460e5d-ce91-49af-a3a5-70b6be7486d1'
DEFAULT_OAUTH2_SCOPES=["https://outlook.office.com/IMAP.AccessAsUser.All", "https://outlook.office.com/SMTP.Send"]

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
    import msal
except ImportError:
    logging.error("Failed to import `msal`, please `pip3 install msal`")
    sys.exit(1)

try:
    import secretstorage
except ImportError:
    logging.error("Failed to import `secretstorage`, please `pip3 install secretstorage`")
    sys.exit(1)



class MicrosoftO365(object):
    def __init__(self, client_id = DEFAULT_OAUTH2_CLIENT_ID, client_credential = None, scopes = DEFAULT_OAUTH2_SCOPES, token_cache_file = None):

        self._scopes = scopes
        self._token_cache_file = token_cache_file
        self._token_cache = msal.SerializableTokenCache()
        if self._token_cache_file is not None:
            if os.path.exists(self._token_cache_file):
                self._token_cache.deserialize(open(self._token_cache_file, "r").read())

        self._app = msal.ConfidentialClientApplication(
                            client_id = client_id,
                            client_credential = client_credential,
                            token_cache = self._token_cache)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self._token_cache_file is not None and self._token_cache.has_state_changed:
            with open(self._token_cache_file, "w") as token_cache_io:
                token_cache_io.write(self._token_cache.serialize())

    def get_token_by_refresh_token(self, refresh_token, interactive = False):
        """
        Fetch and return access token as string.

        If interactive is `False` refresh token is ivalid, raise an
        exception.

        If interactive is `True`, guide user through the
        authentication/authorization process.
        """
        reply = self._app.acquire_token_by_refresh_token(refresh_token=refresh_token, scopes=self._scopes)
        if not reply:
            if interactive:
                auth_request = self._app.initiate_auth_code_flow(scopes = self._scopes, redirect_uri = 'https://login.microsoftonline.com/common/oauth2/nativeclient')
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

                reply = self._app.acquire_token_by_auth_code_flow(auth_code_flow=auth_request, auth_response=auth_response, scopes = self._scopes)
                if "error" in reply:
                    raise Exception(reply["error_description"])
            else:
                raise Exception('Cannot (re)fetch access token: cache missing or expired and not interactive')
        if not 'access_token' in reply:
            raise Exception('Oops, no access token in reply!')
        return reply['access_token']

    def get_token(self, interactive = False):
        """
        Fetch and return access token as string.

        If interactive is `False` and token cache is either not
        configured or suitable refresh token is not there,
        raise an exception.

        If interactive is `True`, guide user through the
        authentication/authorization process.
        """

        reply = self._app.acquire_token_silent(self._scopes, account=None)
        if reply:
            access_token = reply['access_token']
        else:
            # Extract the refresh token manually, sigh
            refresh_tokens = self._token_cache.find('RefreshToken')
            if len(refresh_tokens) > 0:
                refresh_token = refresh_tokens[0]['secret']
            else:
                refresh_token = 'BOGUS'
            access_token = self.get_token_by_refresh_token(refresh_token)
        return access_token

    def get_token_by_refresh_token_in_secret(self, secret_title, interactive = False):
        """
        Fetch and return access token as string using refresh token stored
        in secret name secret_title.

        If interactive is `False` and refresh token invalid,
        raise an exception.

        If interactive is `True` and refresh token invalid, guide user
        through the authentication/authorization process.

        CAVEAT: For now, it only supports refresh token stored in Evolution
        format.
        """
        secrets = secretstorage.get_default_collection(secretstorage.dbus_init())
        refresh_token = None
        for secret in secrets.search_items({ 'Title' : secret_title }):
            refresh_token_json = json.loads(secret.get_secret().decode('utf8'))
            refresh_token = refresh_token_json['refresh_token']
        if refresh_token is None:
            raise Exception("No such secret: %s" % secret_title)
        return self.get_token_by_refresh_token(refresh_token, interactive)

    def get_username(self):
        accounts = self._app.get_accounts()
        if len(accounts) > 0:
            return accounts[0]['username']
        else:
            raise Exception("No accounts available, call 'get_token' first!")

    def get_imap_auth_string(self):
        token = self.get_token()
        username = self.get_username()
        return f"user={username}\x01auth=Bearer {token}\x01\x01"


if __name__ == '__main__':
    import argparse
    import sys
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-o", "--output", metavar="FILE",
                        dest='output', default='-',
                        help="Where to write access token, defaults to - (stdout)")
    parser.add_argument("--client_id", metavar="CLIENT_ID",
                        dest='client_id', default=DEFAULT_OAUTH2_CLIENT_ID,
                        help="Client (application) ID, defaults to 'GNOME Evolution` (%s)" % DEFAULT_OAUTH2_CLIENT_ID)
    parser.add_argument("--client_secret", metavar="CLIENT_SECRET",
                        dest='client_credential', default=None,
                        help="Client (application) secret, defaults to none")
    parser.add_argument("--scope", metavar="SCOPE", default=DEFAULT_OAUTH2_SCOPES,
                        dest='scopes', action='append',
                        help="Authorization scope, defaults to %s" % ', '.join(DEFAULT_OAUTH2_SCOPES))
    parser.add_argument("--cache", metavar="CACHE",
                        dest='token_cache_file', default=None,
                        help="Path to token cache file. Either --cache or --secret is allowed, not both.")
    parser.add_argument("--secret",
                        dest='secret', default=None,
                        help="Name (title) of secret service entry containing the refresh token. Either --secret or --cache is allowed, not both.")
    parser.add_argument("--debug",
                        action="store_const", const=True, default=False,
                        help="Enable debugging")
    parser.add_argument("--imap-test",
                        dest='imap_test', action="store_const", const=True, default=False,
                        help="Try to connect to IMAP server to test the token")
    parser.add_argument("--imap-auth-string",
                        dest='imap_auth_string', action="store_const", const=True, default=False,
                        help="Output full IMAP XOAUTH2 authentication string instead of just the token")


    options = parser.parse_args()

    if options.debug:
        sys.excepthook = excepthook
        sys.breakpointhook = breakpointhook

    config = {
        'client_id' : options.client_id,
        'client_credential' : options.client_credential,
        'scopes' : options.scopes,
        'token_cache_file' : options.token_cache_file
    }

    with MicrosoftO365(**config) as provider:
        try:
            if options.imap_test:
                import imaplib
                with imaplib.IMAP4_SSL('outlook.office365.com') as imap:
                    imap.debug = 4
                    imap.authenticate('XOAUTH2', lambda x : provider.get_imap_auth_string())
                    imap.select('inbox')
            else:
                if options.imap_auth_string is True:
                    output_string = provider.get_imap_auth_string()
                elif options.secret is not None:
                    if options.token_cache_file is not None:
                        raise Exception("Either --secret or --cache is allowed, not both.")
                    output_string = provider.get_token_by_refresh_token_in_secret(options.secret, sys.stdout.isatty())
                else:
                    output_string = provider.get_token(sys.stdout.isatty())

                if options.output == '-':
                    print(output_string)
                else:
                    with open(options.output, 'w') as output:
                        output.write(output_string)
        except KeyboardInterrupt:
            pass
        except Exception as e:
            if options.debug:
                raise e
            else:
                logging.error(str(e))
            sys.exit(1)
        sys.exit(0)
