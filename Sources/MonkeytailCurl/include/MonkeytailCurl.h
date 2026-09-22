#ifndef MONKEYTAIL_CURL_H
#define MONKEYTAIL_CURL_H
#include <curl/curl.h>
CURLcode mt_curl_long(CURL *curl, CURLoption option, long value);
CURLcode mt_curl_string(CURL *curl, CURLoption option, const char *value);
CURLcode mt_curl_headers(CURL *curl, struct curl_slist *headers);
CURLcode mt_curl_body(CURL *curl, const void *body, size_t size);
CURLcode mt_curl_ca(CURL *curl, const void *pem, size_t size);
CURLcode mt_curl_callbacks(CURL *curl, void *context, curl_write_callback body, curl_write_callback header);
CURLcode mt_curl_run(CURL *curl, void *context, int (*cancelled)(void *));
long mt_curl_status(CURL *curl);
const char *mt_curl_effective_url(CURL *curl);
#endif
