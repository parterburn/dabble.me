(function() {
  window.DABBLE = window.DABBLE || {};
  DABBLE.webauthn = {
    register: function(nickname) {
      $.ajax({
        url: "/passkeys/registrations/new",
        type: "GET",
        dataType: "json",
        success: function(options) {
          options.challenge = DABBLE.webauthn.bufferDecode(options.challenge);
          options.user.id = DABBLE.webauthn.bufferDecode(options.user.id);
          var excludeCredentials = options.excludeCredentials || options.exclude_credentials;
          if (excludeCredentials) {
            options.excludeCredentials = excludeCredentials.map(function(item) {
              var id = typeof item === 'string' ? item : item.id;
              return {
                type: 'public-key',
                id: DABBLE.webauthn.bufferDecode(id)
              };
            });
          }
          delete options.exclude_credentials;

          navigator.credentials.create({ publicKey: options })
            .then(function(credential) {
              var attestationResponse = {
                id: credential.id,
                rawId: DABBLE.webauthn.bufferEncode(credential.rawId),
                type: credential.type,
                response: {
                  attestationObject: DABBLE.webauthn.bufferEncode(credential.response.attestationObject),
                  clientDataJSON: DABBLE.webauthn.bufferEncode(credential.response.clientDataJSON)
                },
                nickname: nickname
              };

              $.ajax({
                url: "/passkeys/registrations",
                type: "POST",
                headers: {
                  'X-CSRF-Token': $('meta[name="csrf-token"]').attr('content')
                },
                data: JSON.stringify(attestationResponse),
                       contentType: "application/json",
                       success: function() {
                         document.cookie = "dabble_passkey_user_hint=" + encodeURIComponent(options.user.name) + "; path=/; max-age=" + (60*60*24*365);
                         location.reload();
                       },
                       error: function(xhr) {
                  alert("Registration failed: " + xhr.responseJSON.errors.join(", "));
                }
              });
            })
            .catch(function(err) {
              alert("Error creating credential: " + err);
            });
        }
      });
    },

    authenticate: function(email) {
      $.ajax({
        url: "/passkeys/sessions/new",
        type: "GET",
        data: { email: email },
        dataType: "json",
        success: function(options) {
          options.challenge = DABBLE.webauthn.bufferDecode(options.challenge);
          var allowCredentials = options.allowCredentials || options.allow_credentials;
          if (allowCredentials) {
            options.allowCredentials = allowCredentials.map(function(item) {
              var id = typeof item === 'string' ? item : item.id;
              return {
                type: 'public-key',
                id: DABBLE.webauthn.bufferDecode(id)
              };
            });
          }
          delete options.allow_credentials;

          navigator.credentials.get({ publicKey: options })
            .then(function(assertion) {
              var assertionResponse = {
                id: assertion.id,
                rawId: DABBLE.webauthn.bufferEncode(assertion.rawId),
                type: assertion.type,
                response: {
                  authenticatorData: DABBLE.webauthn.bufferEncode(assertion.response.authenticatorData),
                  clientDataJSON: DABBLE.webauthn.bufferEncode(assertion.response.clientDataJSON),
                  signature: DABBLE.webauthn.bufferEncode(assertion.response.signature),
                  userHandle: assertion.response.userHandle ? DABBLE.webauthn.bufferEncode(assertion.response.userHandle) : null
                }
              };

              $.ajax({
                url: "/passkeys/sessions",
                type: "POST",
                headers: {
                  'X-CSRF-Token': $('meta[name="csrf-token"]').attr('content')
                },
                data: JSON.stringify(assertionResponse),
                       contentType: "application/json",
                       success: function(response) {
                         document.cookie = "dabble_passkey_user_hint=" + encodeURIComponent(email) + "; path=/; max-age=" + (60*60*24*365);
                         window.location.href = response.redirect_url;
                       },
                       error: function(xhr) {
                         alert("Authentication failed: " + xhr.responseJSON.errors.join(", "));
                       }
                     });
                   })
                   .catch(function(err) {
                     if (err.name === 'NotAllowedError' || err.name === 'AbortError') {
                       document.cookie = "dabble_passkey_user_hint=; path=/; expires=Thu, 01 Jan 1970 00:00:00 UTC";
                     } else {
                       alert("Error getting credential: " + err);
                     }
                   });
        },
        error: function(xhr) {
          alert("Error: " + xhr.responseJSON.errors.join(", "));
        }
      });
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
    },

    getCookie: function(name) {
      var value = "; " + document.cookie;
      var parts = value.split("; " + name + "=");
      if (parts.length === 2) return decodeURIComponent(parts.pop().split(";").shift());
    }
  };
})();
