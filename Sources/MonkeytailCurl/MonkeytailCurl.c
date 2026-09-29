#include "MonkeytailCurl.h"
CURLcode mt_curl_long(CURL *c, CURLoption o, long v) { return curl_easy_setopt(c, o, v); }
CURLcode mt_curl_string(CURL *c, CURLoption o, const char *v) { return curl_easy_setopt(c, o, v); }
CURLcode mt_curl_headers(CURL *c, struct curl_slist *v) { return curl_easy_setopt(c, CURLOPT_HTTPHEADER, v); }
CURLcode mt_curl_body(CURL *c, const void *body, size_t size) {
    CURLcode code = curl_easy_setopt(c, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)size);
    if (code != CURLE_OK) return code;
    return curl_easy_setopt(c, CURLOPT_COPYPOSTFIELDS, body ? body : "");
}
CURLcode mt_curl_ca(CURL *c, const void *pem, size_t size) {
    struct curl_blob blob = {(void *)pem, size, CURL_BLOB_COPY};
    return curl_easy_setopt(c, CURLOPT_CAINFO_BLOB, &blob);
}
CURLcode mt_curl_callbacks(CURL *c, void *context, curl_write_callback body, curl_write_callback header) {
    CURLcode code;
    if ((code = curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, body)) != CURLE_OK) return code;
    if ((code = curl_easy_setopt(c, CURLOPT_WRITEDATA, context)) != CURLE_OK) return code;
    if ((code = curl_easy_setopt(c, CURLOPT_HEADERFUNCTION, header)) != CURLE_OK) return code;
    return curl_easy_setopt(c, CURLOPT_HEADERDATA, context);
}
CURLcode mt_curl_run(CURL *c, void *context, int (*cancelled)(void *)) {
    CURLM *multi = curl_multi_init();
    if (!multi) return CURLE_OUT_OF_MEMORY;
    CURLcode result = CURLE_FAILED_INIT;
    if (curl_multi_add_handle(multi, c) == CURLM_OK) {
        int running = 1;
        while (running) {
            if (cancelled(context)) { result = CURLE_ABORTED_BY_CALLBACK; break; }
            if (curl_multi_perform(multi, &running) != CURLM_OK) break;
            if (running && curl_multi_poll(multi, NULL, 0, 100, NULL) != CURLM_OK) break;
            if (!running) {
                int remaining;
                CURLMsg *message;
                while ((message = curl_multi_info_read(multi, &remaining))) {
                    if (message->msg == CURLMSG_DONE) result = message->data.result;
                }
            }
        }
        curl_multi_remove_handle(multi, c);
    }
    curl_multi_cleanup(multi);
    return result;
}
long mt_curl_status(CURL *c) { long v = 0; curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &v); return v; }
const char *mt_curl_effective_url(CURL *c) { char *v = NULL; curl_easy_getinfo(c, CURLINFO_EFFECTIVE_URL, &v); return v; }
double mt_curl_time(CURL *c, CURLINFO info) { double v = 0; curl_easy_getinfo(c, info, &v); return v; }
long mt_curl_info_long(CURL *c, CURLINFO info) { long v = 0; curl_easy_getinfo(c, info, &v); return v; }
const char *mt_curl_info_string(CURL *c, CURLINFO info) { char *v = NULL; curl_easy_getinfo(c, info, &v); return v; }
CURLcode mt_curl_debug(CURL *c, void *context, curl_debug_callback callback) {
    CURLcode code;
    if ((code = curl_easy_setopt(c, CURLOPT_DEBUGFUNCTION, callback)) != CURLE_OK) return code;
    if ((code = curl_easy_setopt(c, CURLOPT_DEBUGDATA, context)) != CURLE_OK) return code;
    return curl_easy_setopt(c, CURLOPT_VERBOSE, 1L);
}
double mt_curl_upload_end(CURL *c) { curl_off_t v = 0; curl_easy_getinfo(c, CURLINFO_POSTTRANSFER_TIME_T, &v); return (double)v / 1000000.0; }
