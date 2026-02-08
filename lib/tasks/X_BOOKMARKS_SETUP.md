# X Bookmarks Setup

One-time manual flow to get an OAuth 2.0 **user** token, then save it to your user record. The app auto-refreshes after that — you never need to do this again.

## Prerequisites

In `config/local_env.yml` (from [developer.x.com](https://developer.x.com) → your app → Keys and Tokens):

```yaml
X_CLIENT_ID: your_client_id
X_CLIENT_SECRET: your_client_secret
```

Register this **Callback URL** in the X Developer Portal:

```
http://localhost:3000/x/callback
```

(It doesn't need to be a working page — you just grab the code from the address bar.)

---

## Step 1: Generate a code verifier

```bash
VERIFIER=$(ruby -rsecurerandom -e 'puts SecureRandom.urlsafe_base64(32)')
echo $VERIFIER
```

## Step 2: Generate the code challenge

```bash
CHALLENGE=$(ruby -rdigest -rbase64 -e "puts Base64.urlsafe_encode64(Digest::SHA256.digest('$VERIFIER'), padding: false)")
echo $CHALLENGE
```

## Step 3: Open the authorize URL in your browser

```
https://x.com/i/oauth2/authorize?response_type=code&client_id=YOUR_CLIENT_ID&redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Fx%2Fcallback&scope=bookmark.read%20tweet.read%20users.read%20offline.access&state=xyz&code_challenge=CHALLENGE&code_challenge_method=S256
```

Replace `YOUR_CLIENT_ID` and `CHALLENGE`. Click **Authorize app**. The page will 404 — copy the `code=` value from the address bar.

## Step 4: Exchange the code for tokens (within 30 seconds!)

```bash
curl -s -X POST 'https://api.x.com/2/oauth2/token' \
  -u 'YOUR_CLIENT_ID:YOUR_CLIENT_SECRET' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "grant_type=authorization_code&code=PASTE_CODE_HERE&redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Fx%2Fcallback&code_verifier=$VERIFIER"
```

Response will include `access_token` and `refresh_token`.

## Step 5: Save tokens to your user record

```bash
rake "x:save_tokens[you@email.com,ACCESS_TOKEN,REFRESH_TOKEN]"
```

## Step 6: Fetch bookmarks (auto-refreshes forever)

```bash
rake "x:bookmarks[you@email.com]"
```

Done. The refresh token rotates automatically on each use — no manual steps needed again.
