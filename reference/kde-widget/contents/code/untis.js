/* WebUntis JSON-RPC client for KDE Plasma QML.
 * Mirrors the essential flow from webuntis 2.2.1: QR URI parsing,
 * loginToken generation, cookie-backed JSON-RPC calls, and data mapping.
 */
.pragma library

var LOGIN_TOKEN = "";
var LAST_REQUEST_AT = 0;
var POLL_COOLDOWN_MS = 15 * 60 * 1000;
var sessionCookie = "";
var sessionInfo = null;

function base32Decode(value) {
    var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    var bits = "";
    var input = String(value || "").replace(/=+$/, "").replace(/\s/g, "").toUpperCase();
    for (var i = 0; i < input.length; i++) {
        var index = alphabet.indexOf(input.charAt(i));
        if (index < 0)
            throw new Error("The QR secret is not valid Base32.");
        bits += pad(index.toString(2), 5);
    }
    var bytes = [];
    for (var offset = 0; offset + 8 <= bits.length; offset += 8)
        bytes.push(parseInt(bits.substring(offset, offset + 8), 2));
    return bytes;
}

function sha1(bytes) {
    var words = [], i, j;
    for (i = 0; i < bytes.length; i++)
        words[i >> 2] = (words[i >> 2] || 0) | (bytes[i] << (24 - (i % 4) * 8));
    var bitLength = bytes.length * 8;
    words[bitLength >> 5] = (words[bitLength >> 5] || 0) | (0x80 << (24 - bitLength % 32));
    words[((bitLength + 64 >> 9) << 4) + 15] = bitLength;
    var h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476, h4 = 0xC3D2E1F0;
    for (i = 0; i < words.length; i += 16) {
        var w = [], a = h0, b = h1, c = h2, d = h3, e = h4;
        for (j = 0; j < 80; j++) {
            if (j < 16) w[j] = words[i + j] || 0;
            else w[j] = rol(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);
            var f, k;
            if (j < 20) { f = (b & c) | ((~b) & d); k = 0x5A827999; }
            else if (j < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1; }
            else if (j < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC; }
            else { f = b ^ c ^ d; k = 0xCA62C1D6; }
            var temp = (rol(a, 5) + f + e + k + w[j]) | 0;
            e = d; d = c; c = rol(b, 30); b = a; a = temp;
        }
        h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0; h4 = (h4 + e) | 0;
    }
    return [h0, h1, h2, h3, h4];
}

function rol(value, bits) { return (value << bits) | (value >>> (32 - bits)); }

function hmacSha1(key, message) {
    var block = 64, i;
    if (key.length > block) key = wordsToBytes(sha1(key));
    while (key.length < block) key.push(0);
    var inner = [], outer = [];
    for (i = 0; i < block; i++) { inner.push(key[i] ^ 0x36); outer.push(key[i] ^ 0x5c); }
    return wordsToBytes(sha1(inner.concat(message))).length ? wordsToBytes(sha1(outer.concat(wordsToBytes(sha1(inner.concat(message)))))) : [];
}

function wordsToBytes(words) {
    var bytes = [];
    for (var i = 0; i < words.length; i++)
        bytes.push((words[i] >>> 24) & 255, (words[i] >>> 16) & 255, (words[i] >>> 8) & 255, words[i] & 255);
    return bytes;
}

function totp(secret) {
    var key = base32Decode(secret), counter = Math.floor(Date.now() / 30000), message = [];
    for (var i = 7; i >= 0; i--) message.push(Math.floor(counter / Math.pow(256, i)) & 255);
    var hash = hmacSha1(key, message), offset = hash[hash.length - 1] & 15;
    var code = ((hash[offset] & 127) * 16777216 + hash[offset + 1] * 65536 + hash[offset + 2] * 256 + hash[offset + 3]) % 1000000;
    return pad(code, 6);
}

function findElement(data) {
    if (!data)
        return null;
    if (Array.isArray(data)) {
        for (var i = 0; i < data.length; i++) {
            var arrayElement = findElement(data[i]);
            if (arrayElement)
                return arrayElement;
        }
        return null;
    }
    if (typeof data !== "object")
        return null;
    if (data.elemId !== undefined && data.elemId !== null) {
        return {
            id: data.elemId,
            type: data.elemType !== undefined ? data.elemType : data.elementType
        };
    }
    for (var key in data) {
        var nestedElement = findElement(data[key]);
        if (nestedElement)
            return nestedElement;
    }
    return null;
}

function findPersonFallback(data) {
    if (!data)
        return null;
    if (Array.isArray(data)) {
        for (var i = 0; i < data.length; i++) {
            var arrayPerson = findPersonFallback(data[i]);
            if (arrayPerson)
                return arrayPerson;
        }
        return null;
    }
    if (typeof data !== "object")
        return null;
    var id = data.personId || data.userPersonId;
    if (id)
        return { id: id, type: data.personType };
    for (var key in data) {
        var nestedPerson = findPersonFallback(data[key]);
        if (nestedPerson)
            return nestedPerson;
    }
    return null;
}

function findPerson(data) {
    return findElement(data) || findPersonFallback(data);
}

function personType(value) {
    if (typeof value === "number") return value;
    var map = { STUDENT: 5, SCHUELER: 5, CLASS: 1, KLASSE: 1, TEACHER: 2, LEHRER: 2 };
    return map[String(value || "STUDENT").toUpperCase()] || 5;
}

function decodeQrValue(value) {
    return decodeURIComponent(String(value || "").replace(/\+/g, " "));
}

function parseQr(uri) {
    var value = String(uri || "").trim();
    var lower = value.toLowerCase();
    if (lower.indexOf("untis://setschool?") !== 0)
        throw new Error("The value is not a WebUntis QR URI.");

    var query = value.substring(value.indexOf("?") + 1).split("&");
    var fields = {};
    for (var i = 0; i < query.length; i++) {
        var separator = query[i].indexOf("=");
        if (separator < 1)
            continue;
        fields[decodeQrValue(query[i].substring(0, separator))] = decodeQrValue(query[i].substring(separator + 1));
    }
    if (!fields.url || !fields.school || !fields.user || !fields.key)
        throw new Error("The QR URI is missing url, school, user, or key.");
    fields.url = String(fields.url).trim();
    fields.school = String(fields.school).trim();
    fields.user = String(fields.user).trim();
    fields.key = String(fields.key).trim();
    return fields;
}

function asHost(url) {
    var value = String(url || "").replace(/^https?:\/\//, "").replace(/\/$/, "");
    return value.split("/")[0];
}

function pad(value, size) {
    var result = String(value);
    while (result.length < size)
        result = "0" + result;
    return result;
}

function untisDate(date) {
    return date.getFullYear() + pad(date.getMonth() + 1, 2) + pad(date.getDate(), 2);
}

function jsonRpcUrl(account) {
    return "https://" + asHost(account.url) + "/WebUntis/jsonrpc.do?school=" + encodeURIComponent(account.school);
}

function request(account, method, params, callback, errorCallback) {
    if (!account || !account.url || !account.school) {
        errorCallback("WebUntis credentials are empty: URL or school is missing.");
        return;
    }
    var xhr = new XMLHttpRequest();
    var url = jsonRpcUrl(account);
    xhr.open("POST", url, true);
    xhr.timeout = 20000;
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Accept", "application/json");
    xhr.withCredentials = true;
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
        if (xhr.status < 200 || xhr.status >= 300) {
            errorCallback("WebUntis returned HTTP " + xhr.status + ".");
            return;
        }
        try {
            var result = parseRpcResponse(xhr.responseText);
            if (result.error)
                throw new Error(result.error.message || "WebUntis rejected the request.");
            callback(result.result);
        } catch (error) {
            errorCallback(error.message || "Invalid WebUntis response.");
        }
    };
    xhr.onerror = function() {
        errorCallback("Unable to reach WebUntis for " + method + " (network/TLS error, status " + xhr.status + ", URL " + url + ").");
    };
    xhr.ontimeout = function() {
        errorCallback("WebUntis request timed out for " + method + " (" + url + ").");
    };
    try {
        xhr.send(JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method: method, params: params || {} }));
    } catch (error) {
        errorCallback("Unable to send WebUntis request: " + (error.message || error));
    }
}

function parseResponseBody(text) {
    var body = String(text || "").trim();
    if (!body)
        return "";
    try {
        return JSON.parse(body);
    } catch (error) {
        return body;
    }
}

function parseRpcResponse(text) {
    var response = parseResponseBody(text);
    if (!response || typeof response !== "object")
        throw new Error("WebUntis returned a non-JSON response.");
    return response;
}

function restGet(account, path, token, callback, errorCallback) {
    if (!account || !account.url) {
        errorCallback("WebUntis credentials are empty: URL is missing.");
        return;
    }
    var xhr = new XMLHttpRequest();
    var url = "https://" + asHost(account.url) + path;
    xhr.open("GET", url, true);
    xhr.timeout = 20000;
    xhr.setRequestHeader("Accept", "application/json, text/plain, */*");
    if (token)
        xhr.setRequestHeader("Authorization", "Bearer " + token);
    xhr.withCredentials = true;
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
        if (xhr.status < 200 || xhr.status >= 300) {
            errorCallback("WebUntis returned HTTP " + xhr.status + " for " + path + ".");
            return;
        }
        try {
            callback(parseResponseBody(xhr.responseText));
        } catch (error) {
            errorCallback(error.message || "Invalid WebUntis REST response.");
        }
    };
    xhr.onerror = function() {
        errorCallback("Unable to reach WebUntis REST API (network/TLS error, status " + xhr.status + ", URL " + url + ").");
    };
    xhr.ontimeout = function() {
        errorCallback("WebUntis REST request timed out (" + url + ").");
    };
    xhr.send();
}

function login(account, callback, errorCallback) {
    var qr = parseQr(account.qrPayload);
    sessionInfo = null;
    sessionCookie = "";
    var now = Date.now();
    var xhr = new XMLHttpRequest();
    var host = asHost(qr.url);
    var url = "https://" + host + "/WebUntis/jsonrpc_intern.do?m=getUserData2017&school=" + encodeURIComponent(qr.school) + "&v=i2.2";
    xhr.open("POST", url, true);
    xhr.timeout = 20000;
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Accept", "application/json");
    xhr.withCredentials = true;
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
        if (xhr.status < 200 || xhr.status >= 300) {
            errorCallback("WebUntis returned HTTP " + xhr.status + " during QR login.");
            return;
        }
        try {
            var result = parseRpcResponse(xhr.responseText);
            if (result.error)
                throw new Error(result.error.message || "WebUntis rejected the QR login.");
            sessionInfo = result.result || {};
            var person = findPerson(sessionInfo);
            if (!person)
                throw new Error("WebUntis login succeeded, but no student ID was returned.");
            sessionInfo.personId = person.id;
            sessionInfo.personType = personType(person.type);
            account.url = host;
            account.school = qr.school;
            account.username = qr.user;
            callback(sessionInfo);
        } catch (error) {
            errorCallback(error.message || "Invalid WebUntis login response.");
        }
    };
    xhr.onerror = function() {
        errorCallback("Unable to reach WebUntis during QR login (network/TLS error, status " + xhr.status + ", URL " + url + ").");
    };
    xhr.ontimeout = function() {
        errorCallback("WebUntis QR login timed out (" + url + ").");
    };
    xhr.send(JSON.stringify({
        id: Date.now(),
        method: "getUserData2017",
        params: [{ auth: { clientTime: now, user: qr.user, otp: totp(qr.key) } }],
        jsonrpc: "2.0"
    }));
}

function timetableParams(personId, personTypeValue, start, end) {
    return {
        options: {
            id: Date.now(),
            element: { id: personId, type: personType(personTypeValue) },
            startDate: Number(untisDate(start)),
            endDate: Number(untisDate(end)),
            showLsText: true,
            showStudentgroup: true,
            showLsNumber: true,
            showSubstText: true,
            showInfo: true,
            showBooking: true,
            roomFields: ["id", "name", "longname", "externalkey"],
            teacherFields: ["id", "name", "longname", "externalkey"],
            subjectFields: ["id", "name", "longname", "externalkey"],
            klasseFields: ["id", "name", "longname", "externalkey"]
        }
    };
}

function isSchoolYearRangeError(message) {
    var value = String(message || "").toLowerCase();
    return value.indexOf("single school year") !== -1 ||
        value.indexOf("school year") !== -1 ||
        value.indexOf("schuljahr") !== -1;
}

function getWeek(account, callback, errorCallback) {
    var date = new Date();
    var start = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    var end = new Date(start.getTime() + 6 * 86400000);
    var personId = sessionInfo && sessionInfo.personId;
    var personTypeValue = sessionInfo && sessionInfo.personType;
    if (!personId) {
        errorCallback("The login response did not contain a student ID.");
        return;
    }

    function requestRange(rangeStart, rangeEnd, allowNextWeekRetry) {
        request(account, "getTimetable", timetableParams(personId, personTypeValue, rangeStart, rangeEnd), callback, function(error) {
            if (allowNextWeekRetry && isSchoolYearRangeError(error)) {
                var nextMonday = new Date(rangeStart.getTime());
                var day = nextMonday.getDay();
                nextMonday.setDate(nextMonday.getDate() + (day === 0 ? 1 : 8 - day));
                var nextSunday = new Date(nextMonday.getTime() + 6 * 86400000);
                requestRange(nextMonday, nextSunday, false);
                return;
            }
            errorCallback(error);
        });
    }

    requestRange(start, end, true);
}

function getInbox(account, callback, errorCallback) {
    var token = sessionInfo && sessionInfo.jwt_token;
    if (token) {
        restGet(account, "/WebUntis/api/rest/view/v1/messages", token, callback, errorCallback);
        return;
    }
    restGet(account, "/WebUntis/api/token/new", "", function(response) {
        var jwt = response;
        if (response && typeof response === "object")
            jwt = response.jwt_token || response.jwtToken || response.token || response.access_token || response.result;
        if (jwt && typeof jwt === "object")
            jwt = jwt.jwt_token || jwt.token || jwt.access_token;
        if (!jwt || typeof jwt !== "string") {
            errorCallback("WebUntis did not return an Inbox token.");
            return;
        }
        if (sessionInfo)
            sessionInfo.jwt_token = jwt;
        restGet(account, "/WebUntis/api/rest/view/v1/messages", jwt, callback, errorCallback);
    }, errorCallback);
}

function getData(account, callback, errorCallback, force) {
    if (!account || !account.url || !account.school) {
        errorCallback("WebUntis credentials are empty: URL or school is missing.");
        return;
    }
    var now = Date.now();
    if (!force && LAST_REQUEST_AT && now - LAST_REQUEST_AT < POLL_COOLDOWN_MS) {
        errorCallback("cooldown:" + Math.ceil((POLL_COOLDOWN_MS - (now - LAST_REQUEST_AT)) / 60000));
        return;
    }
    LAST_REQUEST_AT = now;
    getWeek(account, function(week) {
        getInbox(account, function(inbox) {
            callback({ week: week || [], inbox: inbox || {} });
        }, errorCallback);
    }, errorCallback);
}

var SUBJECT_MAP = {
    b: "Bio",
    M: "Mathe",
    ph: "Physik",
    sp: "Sport",
    WI: "Wirtschaft",
    E: "Englisch",
    inf: "Informatik",
    mu: "Musik",
    d: "Deutsch",
    g: "Geschichte",
    eth: "Ethik",
    geo: "Erdkunde"
};

function formatSubject(raw) {
    if (!raw)
        return "?";
    var value = String(raw);
    var id = value.replace(/[0-9]/g, "");
    var name = SUBJECT_MAP[id] || id;
    return /^[A-Z]/.test(value) ? name + " (LK)" : name;
}

function lessonSubject(lesson) {
    var raw = "";
    if (lesson.subjects && lesson.subjects.length)
        raw = lesson.subjects[0].name || lesson.subjects[0].longName;
    else if (lesson.su && lesson.su.length)
        raw = lesson.su[0].name || lesson.su[0].longname;
    return formatSubject(raw);
}

function lessonTeacher(lesson) {
    if (lesson.teachers && lesson.teachers.length)
        return lesson.teachers[0].name || lesson.teachers[0].longName;
    if (lesson.te && lesson.te.length)
        return lesson.te[0].name || lesson.te[0].longname;
    return "";
}

function timetableEntries(value) {
    if (Array.isArray(value))
        return value;
    if (!value || typeof value !== "object")
        return [];
    var candidates = [value.timetable, value.lessons, value.data, value.result];
    for (var i = 0; i < candidates.length; i++) {
        if (Array.isArray(candidates[i]))
            return candidates[i];
        if (candidates[i] && candidates[i] !== value) {
            var nested = timetableEntries(candidates[i]);
            if (nested.length)
                return nested;
        }
    }
    return [];
}

function mapLesson(lesson) {
    var date = String(lesson.date || lesson.dat || "").replace(/-/g, "");
    var start = Number(lesson.startTime || lesson.start || 0);
    var end = Number(lesson.endTime || 0);
    return {
        date: date,
        startTime: pad(Math.floor(start / 100), 2) + ":" + pad(start % 100, 2),
        endTime: pad(Math.floor(end / 100), 2) + ":" + pad(end % 100, 2),
        subject: lessonSubject(lesson),
        teacher: lessonTeacher(lesson),
        info: lesson.lessonText || lesson.lstext || lesson.substText || lesson.info || "",
        cancelled: String(lesson.code || "").toLowerCase() === "cancelled" ||
            String(lesson.code || "").toLowerCase() === "cancel" ||
            String(lesson.cellState || "").toUpperCase() === "CANCELLED" ||
            String(lesson.cellState || "").toUpperCase() === "CANCEL" ||
            lesson.isCancelled === true,
        completed: false
    };
}

function mapInbox(inbox) {
    var list = Array.isArray(inbox) ? inbox : (inbox && (inbox.incomingMessages || inbox.messages) || []);
    return list.slice().sort(function(a, b) {
        return String(b.sentDateTime || b.date || b.createdAt || "").localeCompare(String(a.sentDateTime || a.date || a.createdAt || ""));
    }).slice(0, 5).map(function(item) {
        var sender = item.sender || item.from || {};
        return {
            id: item.id || 0,
            teacher: sender.displayName || sender.name || item.senderName || "WebUntis",
            subject: item.subject || item.title || "Nachricht",
            text: item.content || item.text || item.contentPreview || "",
            sentAt: item.sentDateTime || item.date || item.createdAt || "",
            attachment: item.hasAttachments ? true : (item.attachment || item.attachments || null),
            unread: item.isMessageRead === false,
            reply: item.isReply === true,
            url: item.url || item.link || ""
        };
    });
}

function reset() {
    sessionCookie = "";
    sessionInfo = null;
}

function cooldownMinutes() {
    if (!LAST_REQUEST_AT)
        return 0;
    return Math.max(0, Math.ceil((POLL_COOLDOWN_MS - (Date.now() - LAST_REQUEST_AT)) / 60000));
}

function cooldownMs() { return POLL_COOLDOWN_MS; }
