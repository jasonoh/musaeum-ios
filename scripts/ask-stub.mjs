#!/usr/bin/env node
// A stand-in for a model: OpenAI-compatible, streaming, and honest about what it was sent.
//
//   node scripts/ask-stub.mjs [port=8799] [log=/tmp/ask-stub.log]
//   STUB_RECALL=weak|unknown|strong   what the recall probe is told (default weak)
//   STUB_OPENING='…'                  the section opening a `strong` reply quotes
//
// Point the Mac at it (app_config in the profile's musaeum.db):
//   ai_base_url = http://127.0.0.1:8799/v1
//   ai_model    = stub
//
// The probe is recognised the way the Mac builds it (shared/ask/ask-context.ts, probeSystem): a system
// message carrying the two-line contract `RECALL: <yes|no>` / `OPENING: <…>`. The reply is what
// shared/ask/recall.ts parseProbe reads: `weak` is `RECALL: no`, `strong` is `RECALL: yes` plus an
// OPENING that is checked against the section's first 120 content tokens, `unknown` is prose that
// does not follow the contract (parseProbe returns parsed:false).
//
// Every request is appended to the log as one JSON line (`isProbe`, `messages`, and the bearer header
// presence), and every connection's close is logged too, so "what reached the model" and "did the
// socket close" are read from here and not from the phone.
import { appendFileSync } from 'node:fs'
import { createServer } from 'node:http'

const [port = '8799', log = '/tmp/ask-stub.log'] = process.argv.slice(2)
const recall = process.env.STUB_RECALL ?? 'weak'
const opening = process.env.STUB_OPENING ?? ''

const frame = (text) => `data: ${JSON.stringify({ choices: [{ delta: { content: text } }] })}\n\n`
const write = (entry) => appendFileSync(log, JSON.stringify({ at: new Date().toISOString(), ...entry }) + '\n')

const isProbeMessages = (messages) =>
  messages.some((m) => m.role === 'system' && /RECALL:\s*<yes\|no>/.test(m.content ?? ''))

let serial = 0

createServer((req, res) => {
  const id = ++serial
  let raw = ''
  req.on('data', (chunk) => (raw += chunk))
  req.on('end', () => {
    let body = {}
    try {
      body = JSON.parse(raw)
    } catch {}
    const messages = body.messages ?? []
    const isProbe = isProbeMessages(messages)
    write({
      id,
      event: 'request',
      url: req.url,
      isProbe,
      recall: isProbe ? recall : undefined,
      authorization: req.headers.authorization ? 'present' : 'absent',
      messages
    })

    res.writeHead(200, { 'content-type': 'text/event-stream' })
    const reply = isProbe
      ? recall === 'strong'
        ? `RECALL: yes\nOPENING: ${opening}\n`
        : recall === 'unknown'
          ? 'Certainly! Here is a lovely summary of the book.'
          : 'RECALL: no\nOPENING:\n'
      : 'This passage sets up a contrast that the rest of the section develops. See “Introduction” for the setup.'
    let i = 0
    const timer = setInterval(() => {
      if (i >= reply.length) {
        clearInterval(timer)
        res.end('data: [DONE]\n\n')
        write({ id, event: 'finished' })
        return
      }
      res.write(frame(reply.slice(i, i + 6)))
      i += 6
    }, 60)
    // `res`, not `req`: on current Node `req` closes as soon as its body is read, long before the client goes.
    res.on('close', () => {
      clearInterval(timer)
      write({ id, event: 'closed', sent: Math.min(i, reply.length), of: reply.length })
    })
  })
}).listen(Number(port), '127.0.0.1', () => console.log(`ask stub on :${port}, logging to ${log}`))
