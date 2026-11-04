#!/usr/bin/env python3
"""Add an uploaded build to the public TestFlight group and submit it for beta review.

Submission problems (for example a build already in review) are reported as
warnings and do not fail the run.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = 'https://api.appstoreconnect.apple.com'
APP_ID = os.environ['APP_ID']
PLATFORM = os.environ['PLATFORM']
BUILD_NUMBER = os.environ['BUILD_NUMBER']
GROUP_NAME = os.environ.get('BETA_GROUP', 'Public')
WHATS_NEW = os.environ.get('WHATS_NEW', '').strip()[:4000]
TIMEOUT = int(os.environ.get('PROCESSING_TIMEOUT', '2700'))


class APIError(Exception):
    pass


def token():
    now = int(time.time())
    return jwt.encode({'iss': os.environ['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 900, 'aud': 'appstoreconnect-v1'},
                      os.environ['ASC_KEY_P8'], algorithm='ES256', headers={'kid': os.environ['ASC_KEY_ID']})


def request(method, path, body=None, query=None):
    url = API + path + ('?' + urllib.parse.urlencode(query) if query else '')
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        'Authorization': f'Bearer {token()}', 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req) as response:
            payload = response.read()
    except urllib.error.HTTPError as error:
        details = json.loads(error.read() or b'{}').get('errors', [])
        message = '; '.join(item.get('detail') or item.get('title', '') for item in details)
        raise APIError(f'{method} {path} returned {error.code}: {message}') from None
    return json.loads(payload) if payload else {}


def warn(message):
    print(f'::warning title=TestFlight {PLATFORM}::{message}')


def processed_build():
    deadline = time.time() + TIMEOUT
    while time.time() < deadline:
        builds = request('GET', '/v1/builds', query={
            'filter[app]': APP_ID, 'filter[version]': BUILD_NUMBER,
            'filter[preReleaseVersion.platform]': PLATFORM, 'fields[builds]': 'processingState'})['data']
        state = builds[0]['attributes']['processingState'] if builds else 'NOT_FOUND'
        print(f'Build {BUILD_NUMBER} ({PLATFORM}): {state}')
        if state == 'VALID':
            return builds[0]['id']
        if state in ('FAILED', 'INVALID'):
            print(f'::error title=TestFlight {PLATFORM}::Build {BUILD_NUMBER} processing {state.lower()}')
            sys.exit(1)
        time.sleep(30)
    return None


def set_whats_new(build_id):
    localizations = request('GET', f'/v1/builds/{build_id}/betaBuildLocalizations')['data']
    existing = next((item for item in localizations if item['attributes']['locale'] == 'en-US'), None)
    if existing:
        request('PATCH', f'/v1/betaBuildLocalizations/{existing["id"]}', {'data': {
            'type': 'betaBuildLocalizations', 'id': existing['id'], 'attributes': {'whatsNew': WHATS_NEW}}})
    else:
        request('POST', '/v1/betaBuildLocalizations', {'data': {
            'type': 'betaBuildLocalizations', 'attributes': {'locale': 'en-US', 'whatsNew': WHATS_NEW},
            'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})


def main():
    groups = request('GET', '/v1/betaGroups', query={'filter[app]': APP_ID, 'filter[name]': GROUP_NAME})['data']
    group = next((item for item in groups if item['attributes']['name'] == GROUP_NAME), None)
    if not group:
        print(f'::error title=TestFlight {PLATFORM}::Beta group "{GROUP_NAME}" not found')
        sys.exit(1)
    build_id = processed_build()
    if not build_id:
        warn(f'Build {BUILD_NUMBER} was not processed within {TIMEOUT // 60} minutes; submit it manually.')
        return
    steps = [
        ('set What to Test', lambda: WHATS_NEW and set_whats_new(build_id)),
        (f'add to "{GROUP_NAME}"', lambda: request('POST', f'/v1/betaGroups/{group["id"]}/relationships/builds',
                                                     {'data': [{'type': 'builds', 'id': build_id}]})),
        ('submit for beta review', lambda: request('POST', '/v1/betaAppReviewSubmissions', {'data': {
            'type': 'betaAppReviewSubmissions',
            'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})),
    ]
    for name, action in steps:
        try:
            action()
            print(f'Build {BUILD_NUMBER} ({PLATFORM}): {name} succeeded')
        except APIError as error:
            warn(f'Could not {name} for build {BUILD_NUMBER}: {error}')


if __name__ == '__main__':
    main()
