// Passkey (WebAuthn) glue for LiveView. The server — TheFloor.Accounts.Passkeys —
// owns challenges and all verification. Everything on the wire is base64url
// without padding. Manual conversion (instead of PublicKeyCredential.parse*FromJSON)
// keeps older iPhones (iOS 16/17) working.

const b64url = {
  encode(buffer) {
    let s = ""
    for (const byte of new Uint8Array(buffer)) s += String.fromCharCode(byte)
    return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
  },
  decode(str) {
    const b64 = str.replace(/-/g, "+").replace(/_/g, "/")
    const padded = b64 + "===".slice((b64.length + 3) % 4)
    return Uint8Array.from(atob(padded), c => c.charCodeAt(0)).buffer
  },
}

const supported = () => typeof window.PublicKeyCredential === "function"

const errorPayload = err => ({name: (err && err.name) || "Error", message: (err && err.message) || ""})

// Sign in. Attach to a container holding a <button data-passkey-button>.
// On mount it also starts a "conditional" request so saved passkeys appear in
// the email field's autofill (needs autocomplete="username webauthn").
//
// Safari shows its passkey sheet only for a request started inside the tap,
// so the button's challenge is fetched ahead (`ready`) and a tap asks the
// browser at once. The server keeps one challenge per request ("button",
// "autofill").
export const PasskeyLogin = {
  mounted() {
    this.abort = null
    this.ready = null
    if (!supported()) {
      this.pushEvent("passkey:unsupported", {})
      return
    }
    this.prepare()
    const button = this.el.querySelector("[data-passkey-button]")
    if (button) button.addEventListener("click", () => this.tap())

    const conditional = PublicKeyCredential.isConditionalMediationAvailable
    if (conditional) {
      conditional.call(PublicKeyCredential).then(ok => ok && this.start("conditional")).catch(() => {})
    }
  },

  // A new socket holds no challenges: fetch the button's again.
  reconnected() {
    this.prepare()
  },

  destroyed() {
    if (this.abort) this.abort.abort()
  },

  prepare() {
    this.ready = null
    this.pushEvent("passkey:auth_options", {for: "button"}, options => { this.ready = options })
  },

  tap() {
    const options = this.ready
    if (!options) return this.start("optional")
    this.ready = null
    this.request("optional", options)
  },

  start(mediation) {
    const forName = mediation === "conditional" ? "autofill" : "button"
    this.pushEvent("passkey:auth_options", {for: forName}, options => this.request(mediation, options))
  },

  // Calls the browser before its first await, so a tap's request starts in the tap.
  async request(mediation, options) {
    // Only one request at a time: a button tap supersedes the autofill request.
    if (this.abort) this.abort.abort()
    const abort = new AbortController()
    this.abort = abort
    const forName = mediation === "conditional" ? "autofill" : "button"

    try {
      const credential = await navigator.credentials.get({
        mediation,
        signal: abort.signal,
        publicKey: {
          challenge: b64url.decode(options.challenge),
          rpId: options.rpId,
          userVerification: options.userVerification,
          timeout: options.timeout,
          allowCredentials: [],
        },
      })
      if (!credential) return
      const r = credential.response
      this.pushEvent("passkey:auth", {
        rawId: b64url.encode(credential.rawId),
        clientDataJSON: b64url.encode(r.clientDataJSON),
        authenticatorData: b64url.encode(r.authenticatorData),
        signature: b64url.encode(r.signature),
        userHandle: r.userHandle ? b64url.encode(r.userHandle) : null,
        for: forName,
      })
    } catch (err) {
      // A superseded or autofill request failing is not the person's problem.
      if (abort.signal.aborted || mediation === "conditional") return
      this.pushEvent("passkey:error", errorPayload(err))
      // Cancelled or failed: the next tap needs a fresh challenge.
      this.prepare()
    }
  },
}

// Register this device. Attach to a <button type="button">.
export const PasskeyRegister = {
  mounted() {
    if (!supported()) {
      this.pushEvent("passkey:unsupported", {})
      return
    }
    this.el.addEventListener("click", event => {
      event.preventDefault()
      this.start()
    })
  },

  // A reply lost to a dropped connection must not leave the button dead.
  reconnected() {
    this.busy = false
  },

  start() {
    // A double tap would open a second browser prompt and report the first as cancelled.
    if (this.busy) return
    this.busy = true
    this.pushEvent("passkey:register_options", {}, async o => {
      try {
        const credential = await navigator.credentials.create({
          publicKey: {
            challenge: b64url.decode(o.challenge),
            rp: o.rp,
            user: {id: b64url.decode(o.user.id), name: o.user.name, displayName: o.user.displayName},
            pubKeyCredParams: o.pubKeyCredParams,
            authenticatorSelection: o.authenticatorSelection,
            attestation: o.attestation,
            timeout: o.timeout,
            excludeCredentials: o.excludeCredentials.map(c => ({type: c.type, id: b64url.decode(c.id)})),
          },
        })
        this.pushEvent("passkey:register", {
          rawId: b64url.encode(credential.rawId),
          clientDataJSON: b64url.encode(credential.response.clientDataJSON),
          attestationObject: b64url.encode(credential.response.attestationObject),
        })
      } catch (err) {
        this.pushEvent("passkey:error", errorPayload(err))
      } finally {
        this.busy = false
      }
    })
  },
}
