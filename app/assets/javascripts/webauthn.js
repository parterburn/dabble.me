// Passkey registration and sign-in. Plain JS (no jQuery) so the marketing
// sign-in page can load it on its own; it is also part of application.js.
(function() {
  window.DABBLE = window.DABBLE || {};

  // The old sign-in flow kept the account email in this cookie to pop a
  // passkey prompt on page load. Autofill replaced it; clear any leftovers.
  document.cookie = "dabble_passkey_user_hint=; path=/; max-age=0";

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute("content") : "";
  }

  // Challenges are single use, so never let a cache answer for the server.
  function getJSON(url) {
    return fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin", cache: "no-store" })
      .then(function(response) {
        if (!response.ok) { throw new Error("Request failed: " + response.status); }
        return response.json();
      });
  }

  // Resolves with the parsed body; rejects with { status, errors } on failure.
  function postJSON(url, body) {
    return fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": csrfToken()
      },
      body: JSON.stringify(body)
    }).then(function(response) {
      return response.json().catch(function() { return {}; }).then(function(json) {
        if (!response.ok) { throw { status: response.status, errors: json.errors || ["Unknown error"] }; }
        return json;
      });
    });
  }

  function credentialDescriptors(list) {
    return (list || []).map(function(item) {
      var id = typeof item === "string" ? item : item.id;
      return { type: "public-key", id: webauthn.bufferDecode(id) };
    });
  }

  function isCancel(err) {
    return err && (err.name === "NotAllowedError" || err.name === "AbortError");
  }

  var webauthn = DABBLE.webauthn = {
    supported: function() {
      return !!(window.PublicKeyCredential && navigator.credentials && window.fetch);
    },

    register: function(nickname, currentPassword) {
      getJSON("/passkeys/registrations/new")
        .then(function(options) {
          options.challenge = webauthn.bufferDecode(options.challenge);
          options.user.id = webauthn.bufferDecode(options.user.id);
          options.excludeCredentials = credentialDescriptors(options.excludeCredentials || options.exclude_credentials);
          delete options.exclude_credentials;

          return navigator.credentials.create({ publicKey: options });
        })
        .then(function(credential) {
          return postJSON("/passkeys/registrations", {
            id: credential.id,
            rawId: webauthn.bufferEncode(credential.rawId),
            type: credential.type,
            response: {
              attestationObject: webauthn.bufferEncode(credential.response.attestationObject),
              clientDataJSON: webauthn.bufferEncode(credential.response.clientDataJSON)
            },
            nickname: nickname,
            current_password: currentPassword
          });
        })
        .then(function() {
          location.reload();
        })
        .catch(function(err) {
          if (isCancel(err)) { return; }
          if (err && err.errors) {
            alert("Registration failed: " + err.errors.join(", "));
          } else {
            alert("Error creating credential: " + err);
          }
        });
    },

    // Sign in with any passkey saved for this site. With
    // mediation: "conditional" the browser waits and lists passkeys in the
    // email field's autofill menu (the field needs autocomplete="username webauthn");
    // otherwise it opens its passkey dialog right away.
    //
    // opts.mediation  "conditional" or undefined
    // opts.signal     AbortSignal, to cancel a waiting conditional request
    // opts.rememberMe function returning the "Stay logged in" choice
    // opts.onChallengeRequest  called with the challenge fetch's promise
    //
    // Resolves true once the browser is sent to the signed-in page, false if
    // the prompt was dismissed or aborted. Rejects on other errors: with
    // { status, errors } when the server refused the passkey.
    signIn: function(opts) {
      opts = opts || {};

      var challengeRequest = getJSON("/passkeys/sessions/new");
      if (opts.onChallengeRequest) { opts.onChallengeRequest(challengeRequest); }

      return challengeRequest
        .then(function(options) {
          if (opts.signal && opts.signal.aborted) {
            throw new DOMException("Passkey request was cancelled", "AbortError");
          }
          options.challenge = webauthn.bufferDecode(options.challenge);
          options.allowCredentials = credentialDescriptors(options.allowCredentials || options.allow_credentials);
          delete options.allow_credentials;

          var request = { publicKey: options };
          if (opts.mediation) { request.mediation = opts.mediation; }
          if (opts.signal) { request.signal = opts.signal; }
          return navigator.credentials.get(request);
        })
        .then(function(assertion) {
          return postJSON("/passkeys/sessions", {
            id: assertion.id,
            rawId: webauthn.bufferEncode(assertion.rawId),
            type: assertion.type,
            response: {
              authenticatorData: webauthn.bufferEncode(assertion.response.authenticatorData),
              clientDataJSON: webauthn.bufferEncode(assertion.response.clientDataJSON),
              signature: webauthn.bufferEncode(assertion.response.signature),
              userHandle: assertion.response.userHandle ? webauthn.bufferEncode(assertion.response.userHandle) : null
            },
            remember_me: opts.rememberMe ? opts.rememberMe() : false
          });
        })
        .then(function(response) {
          window.location.href = response.redirect_url;
          return true;
        })
        .catch(function(err) {
          if (isCancel(err)) { return false; }
          throw err;
        });
    },

    // Wires up passkey sign-in on a page: email-field autofill where the
    // browser supports it, plus a button that opens the passkey dialog.
    // config.buttonId, config.rememberMe (function), config.autofill (boolean)
    setupSignIn: function(config) {
      var button = config.buttonId && document.getElementById(config.buttonId);
      if (!webauthn.supported()) {
        if (button) { button.style.display = "none"; }
        return;
      }

      var pending = null;
      // The session holds one challenge, and the last challenge response to
      // arrive wins. Aborting autofill does not stop its challenge fetch, so
      // the button waits for that fetch before asking for its own.
      var autofillChallenge = null;
      var buttonBusy = false;
      // Autofill restarts after a dismissed or refused passkey; the cap keeps
      // a misbehaving browser from looping on challenge requests.
      var autofillStarts = 0;

      function reportFailure(err) {
        if (err && err.errors) {
          alert("Passkey sign-in failed. Try again or log in with your password.");
        } else {
          alert("Unable to start passkey sign-in. Please try again or use your password.");
        }
      }

      // Only one WebAuthn request can be open at a time, so the waiting
      // autofill request is cancelled before the button opens the dialog,
      // and started again afterwards.
      function startAutofill() {
        if (!config.autofill || !PublicKeyCredential.isConditionalMediationAvailable) { return; }
        if (pending || autofillStarts >= 5) { return; }

        PublicKeyCredential.isConditionalMediationAvailable().then(function(available) {
          if (!available || pending) { return; }
          autofillStarts += 1;
          var controller = new AbortController();
          pending = controller;

          webauthn.signIn({
            mediation: "conditional",
            signal: controller.signal,
            rememberMe: config.rememberMe,
            onChallengeRequest: function(request) {
              var settled = function() { if (autofillChallenge === request) { autofillChallenge = null; } };
              autofillChallenge = request;
              request.then(settled, settled);
            }
          })
            .then(function(signedIn) {
              if (pending === controller) { pending = null; }
              if (!signedIn && !controller.signal.aborted) { startAutofill(); }
            })
            .catch(function(err) {
              if (pending === controller) { pending = null; }
              // Stay quiet if autofill could not start: the user did nothing yet.
              if (err && err.errors) {
                reportFailure(err);
                startAutofill();
              }
            });
        });
      }

      if (button) {
        button.addEventListener("click", function(e) {
          e.preventDefault();
          if (buttonBusy) { return; }
          buttonBusy = true;
          if (pending) { pending.abort(); pending = null; }

          var ready = autofillChallenge ? autofillChallenge.catch(function() {}) : Promise.resolve();
          ready
            .then(function() { return webauthn.signIn({ rememberMe: config.rememberMe }); })
            .then(function(signedIn) {
              if (signedIn) { return; }
              buttonBusy = false;
              startAutofill();
            })
            .catch(function(err) {
              buttonBusy = false;
              reportFailure(err);
              startAutofill();
            });
        });
      }

      startAutofill();
    },

    bufferDecode: function(value) {
      if (typeof value !== "string") {
        return value;
      }
      var base64 = value.replace(/-/g, "+").replace(/_/g, "/");
      var pad = base64.length % 4;
      if (pad) {
        if (pad === 1) {
          throw new Error("InvalidLengthError: Input base64url string is the wrong length to determine padding");
        }
        base64 += new Array(5 - pad).join("=");
      }
      return Uint8Array.from(atob(base64), function(c) {
        return c.charCodeAt(0);
      });
    },

    bufferEncode: function(value) {
      return btoa(String.fromCharCode.apply(null, new Uint8Array(value)))
        .replace(/\+/g, "-")
        .replace(/\//g, "_")
        .replace(/=/g, "");
    }
  };
})();
