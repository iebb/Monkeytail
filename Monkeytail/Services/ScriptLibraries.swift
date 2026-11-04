/// Postman sandbox libraries, implemented locally: CryptoJS, lodash and moment subsets, and `require` for the bundled names.
/// They are installed on `globalThis`, so scripts may redeclare them with `var CryptoJS = require('crypto-js')`.
enum ScriptLibraries {
    static let source = #"""
        (() => {
        const CryptoJS = (() => {
          const utf8 = s => new TextEncoder().encode(String(s));
          class WordArray {
            constructor(bytes) { this.bytes = bytes instanceof Uint8Array ? bytes : Uint8Array.from(bytes || []); }
            get sigBytes() { return this.bytes.length; }
            get words() { const words = []; this.bytes.forEach((b, i) => { words[i >>> 2] |= b << (24 - (i % 4) * 8); }); return words; }
            toString(encoder) { return (encoder || Hex).stringify(this); }
            concat(other) { const joined = new Uint8Array(this.bytes.length + other.bytes.length); joined.set(this.bytes); joined.set(other.bytes, this.bytes.length); this.bytes = joined; return this; }
            clone() { return new WordArray(this.bytes.slice()); }
            static create(words, sigBytes) {
              if (words instanceof ArrayBuffer || ArrayBuffer.isView(words)) return new WordArray(new Uint8Array(words.buffer || words, words.byteOffset || 0, words.byteLength).slice());
              words = words || []; const length = sigBytes ?? words.length * 4;
              return new WordArray(Array.from({length}, (_, i) => (words[i >>> 2] >>> (24 - (i % 4) * 8)) & 255));
            }
            static random(count) { return new WordArray(crypto.getRandomValues(new Uint8Array(count))); }
          }
          const latin1 = bytes => { let text = ''; for (let i = 0; i < bytes.length; i += 8192) text += String.fromCharCode(...bytes.subarray(i, i + 8192)); return text; };
          const Hex = {stringify: w => Array.from(w.bytes, b => b.toString(16).padStart(2, '0')).join(''), parse: s => new WordArray((String(s).match(/[0-9a-f]{2}/gi) || []).map(h => parseInt(h, 16)))};
          const Latin1 = {stringify: w => latin1(w.bytes), parse: s => new WordArray(Array.from(String(s), c => c.charCodeAt(0) & 255))};
          const Utf8 = {stringify: w => new TextDecoder('utf-8', {fatal: true}).decode(w.bytes), parse: s => new WordArray(utf8(s))};
          const Base64 = {stringify: w => btoa(latin1(w.bytes)), parse: s => Latin1.parse(atob(String(s).replace(/\s/g, '')))};
          const Base64url = {stringify: w => Base64.stringify(w).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''),
            parse: s => { let text = String(s).replace(/-/g, '+').replace(/_/g, '/'); while (text.length % 4) text += '='; return Base64.parse(text); }};
          const bytesOf = m => m instanceof WordArray ? m.bytes : utf8(m);
          // Round constants are the exact fractional bits of prime square and cube roots.
          const primes = []; for (let n = 2; primes.length < 80; n++) if (primes.every(p => n % p)) primes.push(n);
          const root = (n, k) => { let x = 1n << BigInt(Math.ceil(n.toString(2).length / Number(k)) + 1); for (;;) { const y = ((k - 1n) * x + n / x ** (k - 1n)) / k; if (y >= x) return x; x = y; } };
          const bits = (p, k, width) => root(BigInt(p) << (BigInt(width) * k), k) & ((1n << BigInt(width)) - 1n);
          const K256 = primes.slice(0, 64).map(p => Number(bits(p, 3n, 32)) | 0), H256 = primes.slice(0, 8).map(p => Number(bits(p, 2n, 32)) | 0);
          const K512 = primes.map(p => bits(p, 3n, 64)), H512 = primes.slice(0, 8).map(p => bits(p, 2n, 64));
          const H384 = primes.slice(8, 16).map(p => bits(p, 2n, 64)), H224 = H384.map(v => Number(v & 0xffffffffn) | 0);
          const pad = (message, block, littleEndian) => {
            const width = block === 128 ? 16 : 8, padded = new Uint8Array(Math.ceil((message.length + 1 + width) / block) * block), view = new DataView(padded.buffer), length = message.length * 8;
            padded.set(message); padded[message.length] = 0x80;
            if (littleEndian) { view.setUint32(padded.length - 8, length >>> 0, true); view.setUint32(padded.length - 4, Math.floor(length / 2 ** 32), true); }
            else { view.setUint32(padded.length - 4, length >>> 0); view.setUint32(padded.length - 8, Math.floor(length / 2 ** 32)); }
            return view;
          };
          const rotl = (x, n) => (x << n) | (x >>> (32 - n)), rotr = (x, n) => (x >>> n) | (x << (32 - n));
          const output = (words, littleEndian) => { const view = new DataView(new ArrayBuffer(words.length * 4)); words.forEach((w, i) => view.setInt32(i * 4, w, littleEndian)); return new Uint8Array(view.buffer); };
          const md5 = message => {
            const view = pad(message, 64, true), H = [0x67452301, 0xefcdab89 | 0, 0x98badcfe | 0, 0x10325476];
            const S = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21], K = Array.from({length: 64}, (_, i) => Math.floor(Math.abs(Math.sin(i + 1)) * 2 ** 32) | 0);
            for (let o = 0; o < view.byteLength; o += 64) {
              const M = Array.from({length: 16}, (_, i) => view.getInt32(o + i * 4, true)); let [a, b, c, d] = H;
              for (let i = 0; i < 64; i++) {
                const round = i >> 4, f = [(b & c) | (~b & d), (d & b) | (~d & c), b ^ c ^ d, c ^ (b | ~d)][round], g = [i, 5 * i + 1, 3 * i + 5, 7 * i][round] % 16;
                const next = d; d = c; c = b; b = (b + rotl((a + f + K[i] + M[g]) | 0, S[round * 4 + i % 4])) | 0; a = next;
              }
              H[0] = (H[0] + a) | 0; H[1] = (H[1] + b) | 0; H[2] = (H[2] + c) | 0; H[3] = (H[3] + d) | 0;
            }
            return output(H, true);
          };
          const sha1 = message => {
            const view = pad(message, 64, false), H = [0x67452301, 0xefcdab89 | 0, 0x98badcfe | 0, 0x10325476, 0xc3d2e1f0 | 0], W = [];
            for (let o = 0; o < view.byteLength; o += 64) {
              for (let i = 0; i < 80; i++) W[i] = i < 16 ? view.getInt32(o + i * 4) : rotl(W[i - 3] ^ W[i - 8] ^ W[i - 14] ^ W[i - 16], 1);
              let [a, b, c, d, e] = H;
              for (let i = 0; i < 80; i++) {
                const f = i < 20 ? (b & c) | (~b & d) : i < 40 || i >= 60 ? b ^ c ^ d : (b & c) | (b & d) | (c & d), k = [0x5a827999, 0x6ed9eba1, 0x8f1bbcdc | 0, 0xca62c1d6 | 0][Math.floor(i / 20)];
                const t = (rotl(a, 5) + f + e + k + W[i]) | 0; e = d; d = c; c = rotl(b, 30); b = a; a = t;
              }
              [a, b, c, d, e].forEach((v, i) => { H[i] = (H[i] + v) | 0; });
            }
            return output(H, false);
          };
          const sha256 = (message, iv = H256) => {
            const view = pad(message, 64, false), H = iv.slice(), W = [];
            for (let o = 0; o < view.byteLength; o += 64) {
              for (let i = 0; i < 64; i++) {
                if (i < 16) { W[i] = view.getInt32(o + i * 4); continue; }
                const x = W[i - 15], y = W[i - 2];
                W[i] = (W[i - 16] + (rotr(x, 7) ^ rotr(x, 18) ^ (x >>> 3)) + W[i - 7] + (rotr(y, 17) ^ rotr(y, 19) ^ (y >>> 10))) | 0;
              }
              let [a, b, c, d, e, f, g, h] = H;
              for (let i = 0; i < 64; i++) {
                const t1 = (h + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + K256[i] + W[i]) | 0, t2 = ((rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) | 0;
                h = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0;
              }
              [a, b, c, d, e, f, g, h].forEach((v, i) => { H[i] = (H[i] + v) | 0; });
            }
            return output(H, false);
          };
          const sha512 = (message, iv = H512) => {
            const view = pad(message, 128, false), H = iv.slice(), mask = (1n << 64n) - 1n, r = (x, n) => ((x >> n) | (x << (64n - n))) & mask, W = [];
            for (let o = 0; o < view.byteLength; o += 128) {
              for (let i = 0; i < 80; i++) W[i] = i < 16 ? view.getBigUint64(o + i * 8) : (W[i - 16] + (r(W[i - 15], 1n) ^ r(W[i - 15], 8n) ^ (W[i - 15] >> 7n)) + W[i - 7] + (r(W[i - 2], 19n) ^ r(W[i - 2], 61n) ^ (W[i - 2] >> 6n))) & mask;
              let [a, b, c, d, e, f, g, h] = H;
              for (let i = 0; i < 80; i++) {
                const t1 = (h + (r(e, 14n) ^ r(e, 18n) ^ r(e, 41n)) + ((e & f) ^ (~e & g)) + K512[i] + W[i]) & mask, t2 = ((r(a, 28n) ^ r(a, 34n) ^ r(a, 39n)) + ((a & b) ^ (a & c) ^ (b & c))) & mask;
                h = g; g = f; f = e; e = (d + t1) & mask; d = c; c = b; b = a; a = (t1 + t2) & mask;
              }
              [a, b, c, d, e, f, g, h].forEach((v, i) => { H[i] = (H[i] + v) & mask; });
            }
            const out = new DataView(new ArrayBuffer(64)); H.forEach((v, i) => out.setBigUint64(i * 8, v)); return new Uint8Array(out.buffer);
          };
          const join = (a, b) => { const joined = new Uint8Array(a.length + b.length); joined.set(a); joined.set(b, a.length); return joined; };
          const sha224 = m => sha256(m, H224).slice(0, 28), sha384 = m => sha512(m, H384).slice(0, 48);
          const keyed = (hash, block, key) => {
            let k = bytesOf(key); if (k.length > block) k = hash(k);
            const padded = value => Uint8Array.from({length: block}, (_, i) => (k[i] || 0) ^ value), inner = padded(0x36), outer = padded(0x5c);
            return message => hash(join(outer, hash(join(inner, message))));
          };
          const hmac = (hash, block) => (message, key) => new WordArray(keyed(hash, block, key)(bytesOf(message)));
          const digest = hash => message => new WordArray(hash(bytesOf(message)));
          const progressive = finish => () => {
            let buffered = new Uint8Array(0);
            const self = {update: m => { buffered = join(buffered, bytesOf(m)); return self; }, finalize: m => { if (m !== undefined) self.update(m); const out = new WordArray(finish(buffered)); buffered = new Uint8Array(0); return out; }, reset: () => { buffered = new Uint8Array(0); return self; }};
            return self;
          };
          const hasher = (hash, block) => Object.freeze({create: progressive(hash), _hash: hash, _block: block});
          const algo = {MD5: hasher(md5, 64), SHA1: hasher(sha1, 64), SHA224: hasher(sha224, 64), SHA256: hasher(sha256, 64), SHA384: hasher(sha384, 128), SHA512: hasher(sha512, 128)};
          algo.HMAC = Object.freeze({create: (h, key) => progressive(keyed(h._hash, h._block, key))()});
          const kdfOptions = (cfg = {}, fallback) => ({bytes: (cfg.keySize ?? 4) * 4, hash: (cfg.hasher || fallback)._hash, block: (cfg.hasher || fallback)._block, iterations: cfg.iterations});
          const evpKDF = (password, salt, cfg) => {
            const {bytes, hash} = kdfOptions(cfg, algo.MD5), iterations = cfg?.iterations ?? 1, saltBytes = salt === undefined || salt === null ? new Uint8Array(0) : bytesOf(salt);
            let derived = new Uint8Array(0), block = new Uint8Array(0);
            while (derived.length < bytes) { block = hash(join(join(block, bytesOf(password)), saltBytes)); for (let i = 1; i < iterations; i++) block = hash(block); derived = join(derived, block); }
            return new WordArray(derived.slice(0, bytes));
          };
          const pbkdf2 = (password, salt, cfg) => {
            const {bytes, hash, block} = kdfOptions(cfg, algo.SHA256), iterations = cfg?.iterations ?? 250000, mac = keyed(hash, block, password), saltBytes = bytesOf(salt);
            let derived = new Uint8Array(0);
            for (let index = 1; derived.length < bytes; index++) {
              let u = mac(join(saltBytes, Uint8Array.of(index >>> 24, (index >>> 16) & 255, (index >>> 8) & 255, index & 255))); const t = u.slice();
              for (let i = 1; i < iterations; i++) { u = mac(u); for (let j = 0; j < t.length; j++) t[j] ^= u[j]; }
              derived = join(derived, t);
            }
            return new WordArray(derived.slice(0, bytes));
          };
          // AES (FIPS-197): S-boxes are generated from GF(2^8) inverses rather than embedded as tables.
          const xtime = b => ((b << 1) ^ (b & 0x80 ? 0x1b : 0)) & 255;
          const gmul = (a, b) => { let p = 0; for (; b; b >>= 1, a = xtime(a)) if (b & 1) p ^= a; return p; };
          const sbox = new Uint8Array(256), sboxInverse = new Uint8Array(256), mul = {};
          for (let p = 1, q = 1, first = true; first || p !== 1; first = false) {
            p ^= xtime(p); q ^= q << 1; q ^= q << 2; q ^= q << 4; q &= 255; if (q & 0x80) q ^= 0x09;
            const r8 = n => ((q << n) | (q >>> (8 - n))) & 255, s = q ^ r8(1) ^ r8(2) ^ r8(3) ^ r8(4) ^ 0x63;
            sbox[p] = s; sboxInverse[s] = p;
          }
          sbox[0] = 0x63; sboxInverse[0x63] = 0;
          for (const k of [1, 2, 3, 9, 11, 13, 14]) mul[k] = Uint8Array.from({length: 256}, (_, x) => gmul(x, k));
          const aesKey = key => {
            if (![16, 24, 32].includes(key.length)) throw new Error(`CryptoJS.AES needs a 128-, 192- or 256-bit key, not ${key.length * 8} bits. Pass a passphrase string to derive one.`);
            const nk = key.length / 4, rounds = nk + 6, w = new Uint8Array(16 * (rounds + 1)); w.set(key);
            for (let i = nk, rcon = 1; i < 4 * (rounds + 1); i++) {
              let t = Array.from(w.subarray(4 * i - 4, 4 * i));
              if (i % nk === 0) { t = [sbox[t[1]] ^ rcon, sbox[t[2]], sbox[t[3]], sbox[t[0]]]; rcon = xtime(rcon); }
              else if (nk > 6 && i % nk === 4) t = t.map(b => sbox[b]);
              for (let j = 0; j < 4; j++) w[4 * i + j] = w[4 * (i - nk) + j] ^ t[j];
            }
            const addKey = (s, r) => { for (let i = 0; i < 16; i++) s[i] ^= w[16 * r + i]; };
            const mix = (s, m) => { for (let c = 0; c < 16; c += 4) { const a = s.slice(c, c + 4); for (let j = 0; j < 4; j++) s[c + j] = mul[m[(4 - j) % 4]][a[0]] ^ mul[m[(5 - j) % 4]][a[1]] ^ mul[m[(6 - j) % 4]][a[2]] ^ mul[m[(7 - j) % 4]][a[3]]; } };
            const shift = (s, direction) => { const t = s.slice(); for (let c = 0; c < 4; c++) for (let j = 0; j < 4; j++) s[4 * c + j] = t[4 * ((c + direction * j + 4) % 4) + j]; };
            return {
              encrypt: input => { const s = Uint8Array.from(input); addKey(s, 0); for (let r = 1; r <= rounds; r++) { for (let i = 0; i < 16; i++) s[i] = sbox[s[i]]; shift(s, 1); if (r < rounds) mix(s, [2, 3, 1, 1]); addKey(s, r); } return s; },
              decrypt: input => { const s = Uint8Array.from(input); addKey(s, rounds); for (let r = rounds - 1; r >= 0; r--) { shift(s, -1); for (let i = 0; i < 16; i++) s[i] = sboxInverse[s[i]]; addKey(s, r); if (r) mix(s, [14, 11, 13, 9]); } return s; }
            };
          };
          const xor = (a, b) => a.map((v, i) => v ^ b[i]);
          const mode = Object.freeze(Object.fromEntries(['CBC', 'ECB', 'CFB', 'OFB', 'CTR'].map(name => [name, Object.freeze({name})])));
          const crypt = (bytes, key, iv, modeName, decrypting) => {
            const cipher = aesKey(key), out = new Uint8Array(bytes.length);
            if (modeName !== 'ECB' && !(iv && iv.length >= 16)) throw new Error(`CryptoJS.AES ${modeName} mode with a WordArray key needs a 16-byte iv option.`);
            let previous = iv && iv.slice(0, 16);
            for (let o = 0; o < bytes.length; o += 16) {
              const block = new Uint8Array(16); block.set(bytes.subarray(o, o + 16)); let result;
              if (modeName === 'ECB') result = decrypting ? cipher.decrypt(block) : cipher.encrypt(block);
              else if (modeName === 'CBC') { result = decrypting ? xor(cipher.decrypt(block), previous) : cipher.encrypt(xor(block, previous)); previous = decrypting ? block : result; }
              else if (modeName === 'CFB') { result = xor(block, cipher.encrypt(previous)); previous = decrypting ? block : result; }
              else if (modeName === 'OFB') { previous = cipher.encrypt(previous); result = xor(block, previous); }
              else if (modeName === 'CTR') { result = xor(block, cipher.encrypt(previous)); previous = previous.slice(); const view = new DataView(previous.buffer); view.setUint32(12, (view.getUint32(12) + 1) >>> 0); }
              else throw new Error(`CryptoJS mode ${modeName} is unavailable.`);
              out.set(result.subarray(0, Math.min(16, bytes.length - o)), o);
            }
            return out;
          };
          const padder = (fill, strip) => Object.freeze({pad: (data, words = 4) => { data.bytes = fill(data.bytes, words * 4); }, unpad: data => { data.bytes = strip(data.bytes); }, _fill: fill, _strip: strip});
          const counted = b => b.slice(0, Math.max(0, b.length - (b[b.length - 1] || 0)));
          const zeros = b => { let i = b.length; while (i > 0 && b[i - 1] === 0) i--; return i; };
          const tail = (b, n, last, first, random) => { const k = n - b.length % n, t = random ? crypto.getRandomValues(new Uint8Array(k)) : new Uint8Array(k).fill(last === 'count' ? k : 0); if (last) t[k - 1] = k; if (first) t[0] = first; return join(b, t); };
          const paddings = Object.freeze({
            Pkcs7: padder((b, n) => tail(b, n, 'count'), counted), AnsiX923: padder((b, n) => tail(b, n, true), counted), Iso10126: padder((b, n) => tail(b, n, true, 0, true), counted),
            Iso97971: padder((b, n) => tail(b, n, false, 0x80), b => b.slice(0, Math.max(0, zeros(b) - 1))),
            ZeroPadding: padder((b, n) => join(b, new Uint8Array((n - b.length % n) % n)), b => b.slice(0, zeros(b))), NoPadding: padder(b => b, b => b)
          });
          class CipherParams {
            constructor(values) { Object.assign(this, values); }
            toString(formatter) { return (formatter || this.formatter || format.OpenSSL).stringify(this); }
            static create(values) { return new CipherParams(values); }
          }
          const salted = utf8('Salted__');
          const format = Object.freeze({
            OpenSSL: Object.freeze({stringify: p => Base64.stringify(p.salt ? new WordArray(join(join(salted, p.salt.bytes), p.ciphertext.bytes)) : p.ciphertext),
              parse: text => { const b = Base64.parse(text).bytes, hasSalt = b.length >= 16 && salted.every((v, i) => b[i] === v); return new CipherParams({ciphertext: new WordArray(hasSalt ? b.slice(16) : b), salt: hasSalt ? new WordArray(b.slice(8, 16)) : undefined}); }}),
            Hex: Object.freeze({stringify: p => Hex.stringify(p.ciphertext), parse: text => new CipherParams({ciphertext: Hex.parse(text)})})
          });
          const keyBytes = key => key instanceof WordArray ? key.bytes : ArrayBuffer.isView(key) ? new Uint8Array(key.buffer, key.byteOffset, key.byteLength) : utf8(key);
          const passphrase = (password, salt, cfg) => {
            const s = salt ? (salt instanceof WordArray ? salt : new WordArray(bytesOf(salt))) : WordArray.random(8), derived = evpKDF(password, s, {keySize: 12, hasher: cfg.hasher}).bytes;
            return {salt: s, key: new WordArray(derived.slice(0, 32)), iv: new WordArray(derived.slice(32))};
          };
          const AES = Object.freeze({
            encrypt: (message, key, cfg = {}) => {
              const m = cfg.mode || mode.CBC, padding = cfg.padding || paddings.Pkcs7, derived = typeof key === 'string' ? passphrase(key, cfg.salt, cfg) : {key: new WordArray(keyBytes(key)), iv: cfg.iv};
              const ciphertext = new WordArray(crypt(padding._fill(bytesOf(message), 16), derived.key.bytes, derived.iv && keyBytes(derived.iv), m.name, false));
              return new CipherParams({ciphertext, key: derived.key, iv: derived.iv, salt: derived.salt, algorithm: AES, mode: m, padding, blockSize: 4, formatter: cfg.format || format.OpenSSL});
            },
            decrypt: (ciphertext, key, cfg = {}) => {
              const params = typeof ciphertext === 'string' ? (cfg.format || format.OpenSSL).parse(ciphertext) : ciphertext, m = cfg.mode || mode.CBC, padding = cfg.padding || paddings.Pkcs7;
              const derived = typeof key === 'string' ? passphrase(key, params.salt, cfg) : {key: new WordArray(keyBytes(key)), iv: cfg.iv};
              return new WordArray(padding._strip(crypt(keyBytes(params.ciphertext), derived.key.bytes, derived.iv && keyBytes(derived.iv), m.name, true)));
            }
          });
          const library = {MD5: digest(md5), SHA1: digest(sha1), SHA224: digest(sha224), SHA256: digest(sha256), SHA384: digest(sha384), SHA512: digest(sha512),
            HmacMD5: hmac(md5, 64), HmacSHA1: hmac(sha1, 64), HmacSHA224: hmac(sha224, 64), HmacSHA256: hmac(sha256, 64), HmacSHA384: hmac(sha384, 128), HmacSHA512: hmac(sha512, 128),
            AES, PBKDF2: pbkdf2, EvpKDF: evpKDF, mode, pad: paddings, format, algo: Object.freeze(algo), enc: {Hex, Latin1, Utf8, Base64, Base64url}, lib: {WordArray, CipherParams}};
          for (const name of ['DES', 'TripleDES', 'RC4', 'RC4Drop', 'Rabbit', 'RabbitLegacy', 'Blowfish', 'SHA3', 'RIPEMD160', 'HmacSHA3', 'HmacRIPEMD160'])
            Object.defineProperty(library, name, {get: () => { throw new Error(`CryptoJS.${name} is unavailable in Monkeytail scripts. Available: MD5, SHA1, SHA224, SHA256, SHA384, SHA512, their Hmac variants, AES, PBKDF2, EvpKDF, and enc.`); }});
          return Object.freeze(library);
        })();
        const _ = (() => {
          const own = (o, k) => o != null && Object.prototype.hasOwnProperty.call(Object(o), k);
          const unsafe = k => k === '__proto__' || k === 'constructor' || k === 'prototype';
          const isObject = v => v !== null && (typeof v === 'object' || typeof v === 'function');
          const isPlainObject = v => { if (Object.prototype.toString.call(v) !== '[object Object]') return false; const proto = Object.getPrototypeOf(v); return proto === null || Object.getPrototypeOf(proto) === null; };
          const toPath = p => Array.isArray(p) ? p.map(String) : String(p).replace(/\[(?:'([^']*)'|"([^"]*)"|([^\]]*))\]/g, (m, a, b, c) => '.' + (a ?? b ?? c)).split('.').filter(k => k !== '');
          const get = (o, p, fallback) => { let v = o; for (const k of toPath(p)) { if (v == null) return fallback; v = v[k]; } return v === undefined ? fallback : v; };
          const has = (o, p) => { let v = o; for (const k of toPath(p)) { if (!own(v, k)) return false; v = v[k]; } return true; };
          const set = (o, p, value) => {
            if (!isObject(o)) return o; const keys = toPath(p); if (keys.some(unsafe)) return o; let v = o;
            keys.forEach((k, i) => { if (i === keys.length - 1) v[k] = value; else { if (!isObject(v[k])) v[k] = /^\d+$/.test(keys[i + 1]) ? [] : {}; v = v[k]; } });
            return o;
          };
          const unset = (o, p) => { const keys = toPath(p), parent = keys.length > 1 ? get(o, keys.slice(0, -1)) : o; return parent == null || delete parent[keys[keys.length - 1]]; };
          const isEqual = (a, b) => {
            if (a === b || Object.is(a, b)) return true;
            if (a instanceof Date && b instanceof Date) return a.getTime() === b.getTime();
            if (a instanceof RegExp && b instanceof RegExp) return String(a) === String(b);
            if (!isObject(a) || !isObject(b) || Array.isArray(a) !== Array.isArray(b) || Object.getPrototypeOf(a) !== Object.getPrototypeOf(b)) return false;
            const ka = Object.keys(a), kb = Object.keys(b);
            return ka.length === kb.length && ka.every(k => own(b, k) && isEqual(a[k], b[k]));
          };
          const isMatch = (o, source) => Object.keys(source).every(k => o != null && (isPlainObject(source[k]) && isObject(o[k]) ? isMatch(o[k], source[k]) : isEqual(o[k], source[k])));
          const iteratee = f => typeof f === 'function' ? f : f == null ? (v => v) : Array.isArray(f) ? (v => isEqual(get(v, f[0]), f[1])) : typeof f === 'object' ? (v => isMatch(v, f)) : (v => get(v, f));
          const entries = c => c == null ? [] : Array.isArray(c) || typeof c === 'string' ? Array.from(c).map((v, i) => [i, v]) : Object.entries(c);
          const listOf = c => entries(c).map(e => e[1]);
          const cloneDeep = v => Array.isArray(v) ? v.map(cloneDeep) : v instanceof Date ? new Date(v) : isPlainObject(v) ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, cloneDeep(x)])) : v;
          const merge = (target, ...sources) => {
            for (const source of sources) for (const [k, v] of Object.entries(source || {})) {
              if (v === undefined || unsafe(k)) continue;
              if (isPlainObject(v) || Array.isArray(v)) { if (!isObject(target[k])) target[k] = Array.isArray(v) ? [] : {}; merge(target[k], v); } else target[k] = v;
            }
            return target;
          };
          const compare = (a, b) => a === b ? 0 : a === undefined ? 1 : b === undefined ? -1 : a > b ? 1 : a < b ? -1 : 0;
          const orderBy = (c, fields, orders) => {
            const keys = (Array.isArray(fields) ? fields : [fields]).map(iteratee);
            return listOf(c).map((v, i) => ({v, i, k: keys.map(fn => fn(v))})).sort((x, y) => {
              for (let j = 0; j < keys.length; j++) { const r = compare(x.k[j], y.k[j]) * ([].concat(orders || [])[j] === 'desc' ? -1 : 1); if (r) return r; }
              return x.i - y.i;
            }).map(e => e.v);
          };
          const uniq = a => [...new Set(a || [])];
          const uniqBy = (a, f) => { const fn = iteratee(f), seen = new Set(); return (a || []).filter(v => { const k = fn(v); return !seen.has(k) && !!seen.add(k); }); };
          const sum = a => (a || []).reduce((s, v) => v === undefined ? s : s + v, 0);
          const extreme = (a, f, sign) => { const fn = iteratee(f); let best, score; for (const v of a || []) { const s = fn(v); if (s != null && (score === undefined || (s - score) * sign > 0)) { best = v; score = s; } } return best; };
          const words = s => String(s ?? '').replace(/['\u2019]/g, '').match(/[A-Z]{2,}(?=[A-Z][a-z]+[0-9]*|\b)|[A-Z]?[a-z]+[0-9]*|[A-Z]+|[0-9]+/g) || [];
          const upperFirst = s => { s = String(s ?? ''); return s.charAt(0).toUpperCase() + s.slice(1); };
          const trimWith = (s, chars, start, end) => {
            s = String(s ?? ''); if (chars === undefined) return start && end ? s.trim() : start ? s.trimStart() : s.trimEnd();
            const set = new Set(String(chars)); let i = 0, j = s.length;
            if (start) while (i < j && set.has(s[i])) i++;
            if (end) while (j > i && set.has(s[j - 1])) j--;
            return s.slice(i, j);
          };
          const html = {'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'};
          let idCounter = 0;
          const api = {
            get, set, has, unset, isEqual, isMatch, cloneDeep, merge, orderBy, uniq, uniqBy, sum, words, upperFirst, iteratee,
            clone: v => Array.isArray(v) ? v.slice() : v instanceof Date ? new Date(v) : isPlainObject(v) ? {...v} : v,
            keys: o => o == null ? [] : Object.keys(Object(o)), values: o => o == null ? [] : Object.values(Object(o)),
            toPairs: o => Object.entries(o || {}), entries: o => Object.entries(o || {}), fromPairs: p => Object.fromEntries(p || []),
            pick: (o, ...paths) => { const r = {}; for (const p of paths.flat()) if (has(o, p)) set(r, p, get(o, p)); return r; },
            omit: (o, ...paths) => { if (o == null) return {}; const r = cloneDeep({...o}); paths.flat().forEach(p => unset(r, p)); return r; },
            pickBy: (o, f) => { const fn = iteratee(f); return Object.fromEntries(Object.entries(o || {}).filter(([k, v]) => fn(v, k))); },
            omitBy: (o, f) => { const fn = iteratee(f); return Object.fromEntries(Object.entries(o || {}).filter(([k, v]) => !fn(v, k))); },
            mapValues: (o, f) => { const fn = iteratee(f); return Object.fromEntries(Object.entries(o || {}).map(([k, v]) => [k, fn(v, k, o)])); },
            mapKeys: (o, f) => { const fn = iteratee(f); return Object.fromEntries(Object.entries(o || {}).map(([k, v]) => [fn(v, k, o), v])); },
            assign: (t, ...s) => Object.assign(t, ...s), defaults: (t, ...s) => { for (const o of s) for (const [k, v] of Object.entries(o || {})) if (t[k] === undefined && !unsafe(k)) t[k] = v; return t; },
            invert: o => Object.fromEntries(Object.entries(o || {}).map(([k, v]) => [v, k])),
            each: (c, f) => { for (const [k, v] of entries(c)) if (f(v, k, c) === false) break; return c; },
            map: (c, f) => { const fn = iteratee(f); return entries(c).map(([k, v]) => fn(v, k, c)); },
            filter: (c, f) => { const fn = iteratee(f); return entries(c).filter(([k, v]) => fn(v, k, c)).map(e => e[1]); },
            reject: (c, f) => { const fn = iteratee(f); return entries(c).filter(([k, v]) => !fn(v, k, c)).map(e => e[1]); },
            find: (c, f) => { const fn = iteratee(f), e = entries(c).find(([k, v]) => fn(v, k, c)); return e && e[1]; },
            findIndex: (a, f) => (a || []).findIndex(iteratee(f)), findLast: (c, f) => { const fn = iteratee(f), e = entries(c).reverse().find(([k, v]) => fn(v, k, c)); return e && e[1]; },
            some: (c, f) => { const fn = iteratee(f); return entries(c).some(([k, v]) => fn(v, k, c)); },
            every: (c, f) => { const fn = iteratee(f); return entries(c).every(([k, v]) => fn(v, k, c)); },
            reduce: (c, f, ...initial) => { const e = entries(c); let acc = initial.length ? initial[0] : e[0]?.[1]; for (let i = initial.length ? 0 : 1; i < e.length; i++) acc = f(acc, e[i][1], e[i][0], c); return acc; },
            includes: (c, v) => typeof c === 'string' ? c.includes(v) : Object.values(c || {}).some(x => x === v || Object.is(x, v)),
            size: c => c == null ? 0 : typeof c === 'string' || Array.isArray(c) ? c.length : c instanceof Map || c instanceof Set ? c.size : Object.keys(c).length,
            groupBy: (c, f) => { const fn = iteratee(f); return listOf(c).reduce((o, v) => { const k = fn(v); (own(o, k) ? o[k] : (o[k] = [])).push(v); return o; }, {}); },
            keyBy: (c, f) => { const fn = iteratee(f); return listOf(c).reduce((o, v) => { o[fn(v)] = v; return o; }, {}); },
            countBy: (c, f) => { const fn = iteratee(f); return listOf(c).reduce((o, v) => { const k = fn(v); o[k] = (own(o, k) ? o[k] : 0) + 1; return o; }, {}); },
            partition: (c, f) => { const fn = iteratee(f), r = [[], []]; listOf(c).forEach(v => r[fn(v) ? 0 : 1].push(v)); return r; },
            sortBy: (c, ...fields) => orderBy(c, fields.flat().length ? fields.flat() : [v => v]),
            flatten: a => (a || []).flat(1), flattenDeep: a => (a || []).flat(Infinity), compact: a => (a || []).filter(Boolean),
            chunk: (a, n = 1) => { n = Math.max(Math.floor(n), 0); const r = []; if (n) for (let i = 0; i < (a || []).length; i += n) r.push(a.slice(i, i + n)); return r; },
            difference: (a, ...others) => { const s = new Set(others.flat()); return (a || []).filter(v => !s.has(v)); },
            without: (a, ...values) => (a || []).filter(v => !values.includes(v)),
            intersection: (a, ...others) => uniq(a).filter(v => others.every(o => (o || []).includes(v))), union: (...arrays) => uniq(arrays.flat()),
            zip: (...arrays) => Array.from({length: Math.max(0, ...arrays.map(a => a.length))}, (v, i) => arrays.map(a => a[i])),
            zipObject: (k = [], v = []) => Object.fromEntries(k.map((x, i) => [x, v[i]])),
            head: a => a?.[0], first: a => a?.[0], last: a => a?.length ? a[a.length - 1] : undefined, nth: (a, n = 0) => a?.[n < 0 ? a.length + n : n],
            take: (a, n = 1) => (a || []).slice(0, Math.max(0, n)), drop: (a, n = 1) => (a || []).slice(Math.max(0, n)),
            takeRight: (a, n = 1) => n > 0 ? (a || []).slice(-n) : [], dropRight: (a, n = 1) => (a || []).slice(0, Math.max(0, (a || []).length - n)),
            indexOf: (a, v) => (a || []).indexOf(v), reverse: a => a.reverse(), join: (a, s = ',') => (a || []).join(s), concat: (...v) => [].concat(...v),
            range: (start, end, step) => {
              if (end === undefined) { end = start; start = 0; } if (step === undefined) step = end < start ? -1 : 1;
              if (step === 0) return Array(Math.abs(end - start)).fill(start);
              const r = []; for (let x = start; step > 0 ? x < end : x > end; x += step) r.push(x); return r;
            },
            times: (n, f) => Array.from({length: Math.max(0, n)}, (v, i) => iteratee(f)(i)),
            sumBy: (a, f) => sum((a || []).map(iteratee(f))), mean: a => a?.length ? sum(a) / a.length : NaN, meanBy: (a, f) => a?.length ? sum(a.map(iteratee(f))) / a.length : NaN,
            max: a => extreme(a, null, 1), min: a => extreme(a, null, -1), maxBy: (a, f) => extreme(a, f, 1), minBy: (a, f) => extreme(a, f, -1),
            clamp: (n, lo, hi) => Math.min(Math.max(n, lo), hi), inRange: (n, a, b) => { if (b === undefined) { b = a; a = 0; } return n >= Math.min(a, b) && n < Math.max(a, b); },
            random: (lo, hi, floating) => {
              if (typeof hi === 'boolean') { floating = hi; hi = undefined; } if (typeof lo === 'boolean') { floating = lo; lo = undefined; }
              if (lo === undefined && hi === undefined) { lo = 0; hi = 1; } else if (hi === undefined) { hi = lo; lo = 0; }
              if (lo > hi) [lo, hi] = [hi, lo];
              return floating || lo % 1 || hi % 1 ? lo + Math.random() * (hi - lo) : lo + Math.floor(Math.random() * (hi - lo + 1));
            },
            sample: c => { const list = listOf(c); return list[Math.floor(Math.random() * list.length)]; },
            shuffle: c => { const list = listOf(c); for (let i = list.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [list[i], list[j]] = [list[j], list[i]]; } return list; },
            isNil: v => v == null, isNull: v => v === null, isUndefined: v => v === undefined, isString: v => typeof v === 'string', isNumber: v => typeof v === 'number',
            isBoolean: v => typeof v === 'boolean', isArray: Array.isArray, isObject, isObjectLike: v => v !== null && typeof v === 'object', isPlainObject,
            isFunction: v => typeof v === 'function', isDate: v => v instanceof Date, isRegExp: v => v instanceof RegExp, isNaN: v => typeof v === 'number' && Number.isNaN(v),
            isFinite: Number.isFinite, isInteger: Number.isInteger,
            isEmpty: v => v == null ? true : typeof v === 'string' || Array.isArray(v) ? v.length === 0 : v instanceof Map || v instanceof Set ? v.size === 0 : typeof v === 'object' ? Object.keys(v).length === 0 : true,
            toString: v => v == null ? '' : String(v), toNumber: Number, toInteger: v => Math.trunc(Number(v)) || 0, toArray: listOf,
            camelCase: s => words(s).map((w, i) => i ? upperFirst(w.toLowerCase()) : w.toLowerCase()).join(''),
            kebabCase: s => words(s).map(w => w.toLowerCase()).join('-'), snakeCase: s => words(s).map(w => w.toLowerCase()).join('_'),
            startCase: s => words(s).map(upperFirst).join(' '), lowerCase: s => words(s).map(w => w.toLowerCase()).join(' '), upperCase: s => words(s).map(w => w.toUpperCase()).join(' '),
            capitalize: s => upperFirst(String(s ?? '').toLowerCase()), lowerFirst: s => { s = String(s ?? ''); return s.charAt(0).toLowerCase() + s.slice(1); },
            toUpper: s => String(s ?? '').toUpperCase(), toLower: s => String(s ?? '').toLowerCase(),
            trim: (s, c) => trimWith(s, c, true, true), trimStart: (s, c) => trimWith(s, c, true, false), trimEnd: (s, c) => trimWith(s, c, false, true),
            padStart: (s, n, c = ' ') => String(s ?? '').padStart(n, c), padEnd: (s, n, c = ' ') => String(s ?? '').padEnd(n, c),
            pad: (s, n, c = ' ') => { s = String(s ?? ''); const left = Math.floor((n - s.length) / 2); return s.length >= n ? s : s.padStart(s.length + left, c).padEnd(n, c); },
            repeat: (s, n = 1) => String(s ?? '').repeat(Math.max(0, n)), startsWith: (s, t, i) => String(s ?? '').startsWith(t, i), endsWith: (s, t, i) => String(s ?? '').endsWith(t, i),
            split: (s, sep, limit) => String(s ?? '').split(sep, limit), replace: (s, p, r) => String(s ?? '').replace(p, r),
            escape: s => String(s ?? '').replace(/[&<>"']/g, c => html[c]), unescape: s => String(s ?? '').replace(/&(amp|lt|gt|quot|#39);/g, m => Object.keys(html).find(k => html[k] === m)),
            escapeRegExp: s => String(s ?? '').replace(/[\\^$.*+?()[\]{}|]/g, '\\$&'),
            truncate: (s, options = {}) => { s = String(s ?? ''); const length = options.length ?? 30, omission = options.omission ?? '...'; return s.length <= length ? s : s.slice(0, Math.max(0, length - omission.length)) + omission; },
            identity: v => v, noop: () => {}, constant: v => () => v, uniqueId: (prefix = '') => prefix + (++idCounter),
            once: f => { let done = false, value; return (...a) => done ? value : (done = true, value = f(...a)); }
          };
          api.forEach = api.each; api.all = api.every; api.any = api.some; api.contains = api.includes;
          const wrap = (value, explicit) => new Proxy({}, {get: (t, name) => {
            if (name === 'value' || name === 'valueOf' || name === 'toJSON') return () => value;
            if (name === 'chain') return () => wrap(value, true);
            if (typeof name !== 'string' || typeof api[name] !== 'function') return undefined;
            return (...a) => { const r = api[name](value, ...a); return explicit || Array.isArray(r) || isPlainObject(r) ? wrap(r, explicit) : r; };
          }});
          const lodash = value => wrap(value, false);
          Object.assign(lodash, api, {chain: value => wrap(value, true), VERSION: '4.17.21-monkeytail'});
          return Object.freeze(lodash);
        })();
        const moment = (() => {
          const aliases = {y: 'year', year: 'year', years: 'year', Q: 'quarter', quarter: 'quarter', quarters: 'quarter', M: 'month', month: 'month', months: 'month',
            w: 'week', week: 'week', weeks: 'week', d: 'day', day: 'day', days: 'day', date: 'day', h: 'hour', hour: 'hour', hours: 'hour',
            m: 'minute', minute: 'minute', minutes: 'minute', s: 'second', second: 'second', seconds: 'second', ms: 'millisecond', millisecond: 'millisecond', milliseconds: 'millisecond'};
          const unit = u => aliases[u] || aliases[String(u || '').toLowerCase()];
          const span = {week: 6048e5, day: 864e5, hour: 36e5, minute: 6e4, second: 1e3, millisecond: 1};
          const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
          const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
          const pad = (n, length = 2) => String(Math.abs(n)).padStart(length, '0');
          const ordinal = n => { const suffix = ['th', 'st', 'nd', 'rd'], v = n % 100; return n + (suffix[(v - 20) % 10] || suffix[v] || suffix[0]); };
          const tokens = /\[([^\]]*)]|YYYY|YY|Q|MMMM|MMM|MM|M|Do|DD|D|dddd|ddd|dd|d|E|e|HH|H|hh|h|mm|m|ss|s|SSS|SS|S|A|a|ZZ|Z|X|x/g;
          const escape = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
          const zoned = (fields, utc, zone) => {
            const [y, mo, d, h, mi, s, ms] = fields;
            if (!(mo >= 0 && mo <= 11 && d >= 1 && d <= new Date(Date.UTC(y, mo + 1, 0)).getUTCDate() && h >= 0 && h <= 23 && mi >= 0 && mi <= 59 && s >= 0 && s <= 59 && ms >= 0 && ms <= 999)) return new Date(NaN);
            if (zone === undefined) return utc ? new Date(Date.UTC(y, mo, d, h, mi, s, ms)) : new Date(y, mo, d, h, mi, s, ms);
            const t = Date.UTC(y, mo, d, h, mi, s, ms); if (/^z$/i.test(zone)) return new Date(t);
            const digits = zone.replace(/\D/g, ''); return new Date(t - (zone[0] === '-' ? -1 : 1) * (Number(digits.slice(0, 2)) * 60 + Number(digits.slice(2))) * 6e4);
          };
          const parseFormat = (text, format, utc) => {
            const specs = {YYYY: '\\d{4}', YY: '\\d{2}', MMMM: '[A-Za-z]+', MMM: '[A-Za-z]+', MM: '\\d{2}', M: '\\d{1,2}', Do: '\\d{1,2}(?:st|nd|rd|th)', DD: '\\d{2}', D: '\\d{1,2}',
              dddd: '[A-Za-z]+', ddd: '[A-Za-z]+',
              HH: '\\d{2}', H: '\\d{1,2}', hh: '\\d{2}', h: '\\d{1,2}', mm: '\\d{2}', m: '\\d{1,2}', ss: '\\d{2}', s: '\\d{1,2}', SSS: '\\d{3}', SS: '\\d{2}', S: '\\d',
              A: '[AaPp][Mm]', a: '[AaPp][Mm]', ZZ: '[+-]\\d{4}|Z', Z: '[+-]\\d{2}:?\\d{2}|Z', X: '-?\\d+(?:\\.\\d+)?', x: '-?\\d+'};
            let source = '', last = 0; const order = [];
            for (const match of format.matchAll(tokens)) {
              source += escape(format.slice(last, match.index)); last = match.index + match[0].length;
              if (match[1] !== undefined) source += escape(match[1]); else if (specs[match[0]]) { source += '(' + specs[match[0]] + ')'; order.push(match[0]); } else source += escape(match[0]);
            }
            source += escape(format.slice(last));
            const found = String(text).match(new RegExp('^\\s*' + source, 'i')); if (!found) return new Date(NaN);
            const fields = [new Date().getFullYear(), 0, 1, 0, 0, 0, 0]; let meridiem = null, zone, epoch;
            order.forEach((token, i) => {
              const v = found[i + 1];
              if (token === 'YYYY') fields[0] = Number(v); else if (token === 'YY') fields[0] = Number(v) + (Number(v) > 68 ? 1900 : 2000);
              else if (token === 'MMMM' || token === 'MMM') fields[1] = months.findIndex(name => name.slice(0, 3).toLowerCase() === v.slice(0, 3).toLowerCase());
              else if (token[0] === 'M') fields[1] = Number(v) - 1; else if (token[0] === 'D') fields[2] = parseInt(v, 10);
              else if (/^[Hh]/.test(token)) fields[3] = Number(v); else if (token[0] === 'm') fields[4] = Number(v); else if (token[0] === 's') fields[5] = Number(v);
              else if (token[0] === 'S') fields[6] = Number(v.padEnd(3, '0')); else if (/^[Aa]$/.test(token)) meridiem = /p/i.test(v);
              else if (token[0] === 'Z') zone = v; else if (token === 'X') epoch = Number(v) * 1000; else if (token === 'x') epoch = Number(v);
            });
            if (epoch !== undefined) return new Date(epoch);
            if (fields[1] < 0) return new Date(NaN);
            if (meridiem !== null) { if (meridiem && fields[3] < 12) fields[3] += 12; if (!meridiem && fields[3] === 12) fields[3] = 0; }
            return zoned(fields, utc, zone);
          };
          const parse = (input, format, utc) => {
            if (input === undefined) return new Date();
            if (input === null || input === '') return new Date(NaN);
            if (input instanceof Moment) return new Date(input._d);
            if (input instanceof Date || typeof input === 'number') return new Date(input);
            if (Array.isArray(input)) { const [y, mo = 0, d = 1, h = 0, mi = 0, s = 0, ms = 0] = input; return zoned([y, mo, d, h, mi, s, ms], utc); }
            if (typeof input === 'object') return parse([input.year ?? input.y ?? new Date().getFullYear(), input.month ?? input.M ?? 0, input.date ?? input.day ?? input.d ?? 1, input.hour ?? input.h ?? 0, input.minute ?? input.m ?? 0, input.second ?? input.s ?? 0, input.millisecond ?? input.ms ?? 0], undefined, utc);
            if (format) {
              for (const f of [].concat(format)) { const date = parseFormat(input, f, utc); if (!Number.isNaN(date.getTime())) return date; }
              return new Date(NaN);
            }
            const iso = String(input).trim().match(/^(\d{4})-?(\d{2})-?(\d{2})(?:[T ](\d{2}):?(\d{2})(?::?(\d{2})(?:[.,](\d+))?)?)?\s*(Z|[+-]\d{2}(?::?\d{2})?)?$/i);
            if (iso) { const [, y, mo, d, h = 0, mi = 0, s = 0, frac = '0', zone] = iso; return zoned([+y, mo - 1, +d, +h, +mi, +s, Number(frac.padEnd(3, '0').slice(0, 3))], utc, zone && zone.length === 3 ? zone + '00' : zone); }
            return new Date(String(input));
          };
          class Moment {
            constructor(date, utc) { this._d = date; this._isUTC = !!utc; this._isAMomentObject = true; }
            _get(part) { return this._d[(this._isUTC ? 'getUTC' : 'get') + part](); }
            _set(part, ...v) { this._d[(this._isUTC ? 'setUTC' : 'set') + part](...v); return this; }
            isValid() { return !Number.isNaN(this._d.getTime()); }
            valueOf() { return this._d.getTime(); }
            unix() { return Math.floor(this.valueOf() / 1000); }
            toDate() { return new Date(this._d); }
            toISOString() { return this.isValid() ? this._d.toISOString() : null; }
            toJSON() { return this.toISOString(); }
            toString() { return this.isValid() ? this.format('ddd MMM DD YYYY HH:mm:ss [GMT]ZZ') : 'Invalid date'; }
            locale() { return this; }
            clone() { return new Moment(new Date(this._d), this._isUTC); }
            utc() { this._isUTC = true; return this; }
            local() { this._isUTC = false; return this; }
            isUTC() { return this._isUTC; }
            utcOffset() { return this._isUTC ? 0 : -this._d.getTimezoneOffset(); }
            daysInMonth() { return new Date(Date.UTC(this._get('FullYear'), this._get('Month') + 1, 0)).getUTCDate(); }
            isLeapYear() { const y = this._get('FullYear'); return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0; }
            dayOfYear() { const start = Date.UTC(this._get('FullYear'), 0, 1), now = Date.UTC(this._get('FullYear'), this._get('Month'), this._get('Date')); return Math.round((now - start) / 864e5) + 1; }
            quarter() { return Math.floor(this._get('Month') / 3) + 1; }
            get(u) { return this[u === 'date' || u === 'D' ? 'date' : unit(u)](); }
            set(u, v) { if (typeof u === 'object') { for (const [k, x] of Object.entries(u)) this.set(k, x); return this; } return this[u === 'date' || u === 'D' ? 'date' : unit(u)](v); }
            add(amount, u) {
              if (typeof amount === 'object' && amount !== null) { for (const [k, v] of Object.entries(amount)) this.add(v, k); return this; }
              const n = Number(amount), name = unit(u) || 'millisecond'; if (!n) return this;
              if (name === 'year' || name === 'quarter' || name === 'month') {
                const day = this._get('Date'); this._set('Date', 1); this._set('Month', this._get('Month') + n * (name === 'year' ? 12 : name === 'quarter' ? 3 : 1));
                return this._set('Date', Math.min(day, this.daysInMonth()));
              }
              if (name === 'day' || name === 'week') return this._set('Date', this._get('Date') + n * (name === 'week' ? 7 : 1));
              this._d = new Date(this.valueOf() + n * span[name]); return this;
            }
            subtract(amount, u) {
              if (typeof amount === 'object' && amount !== null) { for (const [k, v] of Object.entries(amount)) this.add(-v, k); return this; }
              return this.add(-Number(amount), u);
            }
            startOf(u) {
              const name = unit(u);
              if (name === 'week') { this._set('Date', this._get('Date') - this._get('Day')); return this.startOf('day'); }
              if (name === 'quarter') { this._set('Month', Math.floor(this._get('Month') / 3) * 3, 1); return this.startOf('day'); }
              if (name === 'year') this._set('Month', 0, 1);
              if (name === 'month') this._set('Date', 1);
              if (['year', 'month', 'day'].includes(name)) this._set('Hours', 0, 0, 0, 0);
              if (name === 'hour') this._set('Minutes', 0, 0, 0);
              if (name === 'minute') this._set('Seconds', 0, 0);
              if (name === 'second') this._set('Milliseconds', 0);
              return this;
            }
            endOf(u) { return unit(u) ? this.startOf(u).add(1, u).subtract(1, 'ms') : this; }
            diff(input, u, float) {
              const other = moment(input), name = unit(u) || 'millisecond';
              const monthDiff = (a, b) => {
                if (a.date() < b.date()) return -monthDiff(b, a);
                const whole = (b.year() - a.year()) * 12 + (b.month() - a.month()), anchor = a.clone().add(whole, 'month');
                const next = b - anchor < 0 ? a.clone().add(whole - 1, 'month') : a.clone().add(whole + 1, 'month');
                return -(whole + (b - anchor < 0 ? (b - anchor) / (anchor - next) : (b - anchor) / (next - anchor))) || 0;
              };
              const value = ['year', 'quarter', 'month'].includes(name) ? monthDiff(this, other) / (name === 'year' ? 12 : name === 'quarter' ? 3 : 1) : (this.valueOf() - other.valueOf()) / span[name];
              return float ? value : value < 0 ? Math.ceil(value) || 0 : Math.floor(value);
            }
            isBefore(input, u) { return unit(u) ? this.clone().endOf(u).valueOf() < moment(input).valueOf() : this.valueOf() < moment(input).valueOf(); }
            isAfter(input, u) { return unit(u) ? moment(input).valueOf() < this.clone().startOf(u).valueOf() : this.valueOf() > moment(input).valueOf(); }
            isSame(input, u) { const t = moment(input).valueOf(); return unit(u) ? this.clone().startOf(u).valueOf() <= t && t <= this.clone().endOf(u).valueOf() : this.valueOf() === t; }
            isSameOrBefore(input, u) { return this.isSame(input, u) || this.isBefore(input, u); }
            isSameOrAfter(input, u) { return this.isSame(input, u) || this.isAfter(input, u); }
            isBetween(a, b, u) { return this.isAfter(a, u) && this.isBefore(b, u); }
            from(input, withoutSuffix) {
              const seconds = (this.valueOf() - moment(input).valueOf()) / 1000, a = Math.abs(seconds);
              const text = a < 45 ? 'a few seconds' : a < 90 ? 'a minute' : a < 2700 ? Math.round(a / 60) + ' minutes' : a < 5400 ? 'an hour' : a < 79200 ? Math.round(a / 3600) + ' hours'
                : a < 129600 ? 'a day' : a < 2246400 ? Math.round(a / 86400) + ' days' : a < 3888000 ? 'a month' : a < 27648000 ? Math.round(a / 2592000) + ' months' : a < 47304000 ? 'a year' : Math.round(a / 31536000) + ' years';
              return withoutSuffix ? text : seconds < 0 ? text + ' ago' : 'in ' + text;
            }
            fromNow(withoutSuffix) { return this.from(undefined, withoutSuffix); }
            to(input, withoutSuffix) { return moment(input).from(this, withoutSuffix); }
            toNow(withoutSuffix) { return moment().from(this, withoutSuffix); }
            format(format) {
              if (!this.isValid()) return 'Invalid date';
              const f = format || (this._isUTC ? 'YYYY-MM-DDTHH:mm:ss[Z]' : 'YYYY-MM-DDTHH:mm:ssZ');
              const Y = this._get('FullYear'), M = this._get('Month'), D = this._get('Date'), d = this._get('Day'), H = this._get('Hours'), m = this._get('Minutes'), s = this._get('Seconds'), S = this._get('Milliseconds');
              const offset = this.utcOffset(), zone = separator => (offset < 0 ? '-' : '+') + pad(Math.floor(Math.abs(offset) / 60)) + separator + pad(Math.abs(offset) % 60);
              const values = {YYYY: pad(Y, 4), YY: pad(Y % 100), Q: Math.floor(M / 3) + 1, MMMM: months[M], MMM: months[M].slice(0, 3), MM: pad(M + 1), M: M + 1, Do: ordinal(D), DD: pad(D), D,
                dddd: weekdays[d], ddd: weekdays[d].slice(0, 3), dd: weekdays[d].slice(0, 2), d, E: d || 7, e: d, HH: pad(H), H, hh: pad(H % 12 || 12), h: H % 12 || 12,
                mm: pad(m), m, ss: pad(s), s, SSS: pad(S, 3), SS: pad(Math.floor(S / 10)), S: Math.floor(S / 100), A: H < 12 ? 'AM' : 'PM', a: H < 12 ? 'am' : 'pm',
                ZZ: zone(''), Z: zone(':'), X: this.unix(), x: this.valueOf()};
              return f.replace(tokens, (token, literal) => literal !== undefined ? literal : String(values[token]));
            }
          }
          for (const [names, part] of [[['year', 'years'], 'FullYear'], [['month', 'months'], 'Month'], [['date', 'dates'], 'Date'], [['hour', 'hours'], 'Hours'], [['minute', 'minutes'], 'Minutes'], [['second', 'seconds'], 'Seconds'], [['millisecond', 'milliseconds'], 'Milliseconds']])
            for (const name of names) Moment.prototype[name] = function (v) { return v === undefined ? this._get(part) : this._set(part, v); };
          for (const [names, part] of [[['year', 'years'], 'FullYear'], [['month', 'months'], 'Month']])
            for (const name of names) Moment.prototype[name] = function (v) { if (v === undefined) return this._get(part); const day = this._get('Date'); this._set('Date', 1); this._set(part, v); return this._set('Date', Math.min(day, this.daysInMonth())); };
          Moment.prototype.day = Moment.prototype.days = Moment.prototype.weekday = function (v) { return v === undefined ? this._get('Day') : this.add(v - this._get('Day'), 'day'); };
          Moment.prototype.isoWeekday = function (v) { return v === undefined ? this._get('Day') || 7 : this.add(v - (this._get('Day') || 7), 'day'); };
          const create = (input, format, utc) => input instanceof Moment && !format ? new Moment(new Date(input._d), utc || input._isUTC) : new Moment(parse(input, typeof format === 'string' || Array.isArray(format) ? format : undefined, utc), utc);
          const moment = (input, format) => create(input, format, false);
          const duration = (amount, u) => {
            const lengths = {...span, month: 2592e6, quarter: 7776e6, year: 31536e6};
            const total = typeof amount === 'object' && amount !== null ? Object.entries(amount).reduce((t, [k, v]) => t + Number(v) * (lengths[unit(k)] || 0), 0) : Number(amount) * (lengths[unit(u) || 'millisecond'] || 1);
            const part = (size, modulo) => Math.trunc(total / size) % modulo;
            return Object.freeze({asMilliseconds: () => total, asSeconds: () => total / 1e3, asMinutes: () => total / 6e4, asHours: () => total / 36e5, asDays: () => total / 864e5, asWeeks: () => total / 6048e5,
              as: k => total / (lengths[unit(k)] || 1), milliseconds: () => part(1, 1000), seconds: () => part(1e3, 60), minutes: () => part(6e4, 60), hours: () => part(36e5, 24), days: () => Math.trunc(total / 864e5),
              humanize: suffix => moment(0).from(moment(-total), !suffix), valueOf: () => total, toISOString: () => 'PT' + total / 1000 + 'S', toJSON: () => 'PT' + total / 1000 + 'S'});
          };
          Object.assign(moment, {utc: (input, format) => create(input, format, true), unix: seconds => new Moment(new Date(seconds * 1000)), isMoment: v => v instanceof Moment,
            isDate: v => v instanceof Date, duration, invalid: () => new Moment(new Date(NaN)), now: () => Date.now(), version: '2.30.1-monkeytail', ISO_8601: undefined,
            min: (...list) => list.flat().reduce((a, b) => moment(b).isBefore(a) ? moment(b) : a, moment(list.flat()[0])),
            max: (...list) => list.flat().reduce((a, b) => moment(b).isAfter(a) ? moment(b) : a, moment(list.flat()[0])),
            months: () => months.slice(), weekdays: () => weekdays.slice(), locale: () => 'en'});
          return Object.freeze(moment);
        })();
        const require = name => {
          const parts = {'hmac-md5': 'HmacMD5', 'hmac-sha1': 'HmacSHA1', 'hmac-sha224': 'HmacSHA224', 'hmac-sha256': 'HmacSHA256', 'hmac-sha384': 'HmacSHA384', 'hmac-sha512': 'HmacSHA512', md5: 'MD5', sha1: 'SHA1', sha224: 'SHA224', sha256: 'SHA256', sha384: 'SHA384', sha512: 'SHA512', aes: 'AES', pbkdf2: 'PBKDF2', evpkdf: 'EvpKDF'};
          const encoders = {'enc-hex': 'Hex', 'enc-latin1': 'Latin1', 'enc-utf8': 'Utf8', 'enc-base64': 'Base64', 'enc-base64url': 'Base64url'};
          const modules = {'crypto-js': CryptoJS, lodash: _, moment, atob: globalThis.atob.bind(globalThis), btoa: globalThis.btoa.bind(globalThis), uuid: Object.freeze({v4: () => crypto.randomUUID()})};
          const sub = String(name).startsWith('crypto-js/') ? String(name).slice(10) : null;
          if (sub !== null && parts[sub]) return CryptoJS[parts[sub]];
          if (sub !== null && encoders[sub]) return CryptoJS.enc[encoders[sub]];
          if (sub !== null && /^(mode|pad)-/.test(sub)) { const group = CryptoJS[sub.slice(0, sub.indexOf('-'))], found = Object.keys(group).find(k => k.toLowerCase() === sub.slice(sub.indexOf('-') + 1)); if (found) return group[found]; }
          if (sub === 'format-openssl' || sub === 'format-hex') return CryptoJS.format[sub === 'format-hex' ? 'Hex' : 'OpenSSL'];
          if (sub === 'core' || sub === 'cipher-core' || sub === 'lib-typedarrays') return CryptoJS;
          if (String(name).startsWith('lodash/') && typeof _[String(name).slice(7)] === 'function') return _[String(name).slice(7)];
          if (Object.prototype.hasOwnProperty.call(modules, name)) return modules[name];
          throw new Error(`require('${name}') is unavailable. Built-in modules: crypto-js, lodash, moment, atob, btoa, uuid.`);
        };
        for (const [name, value] of Object.entries({CryptoJS, _, moment, require})) Object.defineProperty(globalThis, name, {value, writable: true, configurable: true});
        })();
        """#
}
