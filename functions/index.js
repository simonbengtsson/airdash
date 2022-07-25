import functions from 'firebase-functions'
import admin from 'firebase-admin'
import fetch from 'node-fetch';

admin.initializeApp();

class ServerError extends Error {
  constructor(type, statusCode, message = 'Server error') {
      super(message)
      this.name = this.constructor.name
      this.type = type
      this.statusCode = statusCode
  }
}

export const playground = functions.https.onRequest(async (req, res) => {
  functions.logger.log('Playground started')
  await new Promise(resolve => setTimeout(resolve, 1000))
  functions.logger.log('Playground ended')
  res.send('Hello!')
});

async function getFreshTwilioIceServers() {
  const accountSid = process.env.TWILIO_ACCOUNT_SID
  const apiKeySid = process.env.TWILIO_API_KEY_SID
  const apiKeySecret = process.env.TWILIO_API_KEY_SECRET

  if (!accountSid || !apiKeySecret || !apiKeySid) {
    functions.logger.log('Environment', { apiKeySid, accountSid, secret: apiKeySecret?.substring(0, 5) })
    throw new ServerError('invalidEnvironment', 500)
  }

  const url = `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Tokens.json`
  const authString = Buffer.from(`${apiKeySid}:${apiKeySecret}`).toString('base64')
  const headers = {'Authorization': `Basic ${authString}`}
  const response = await fetch(url, { method: 'POST', headers });
  const data = await response.json();

  return data.ice_servers
}

export const updateTwilioToken = functions
  .runWith({})
  .pubsub.schedule('every 6 hours')
  .onRun(async () => {
    const iceServers = await getFreshTwilioIceServers()
    const connectionConfig = {
      date: new Date().toISOString(),
      iceServers: JSON.stringify(iceServers),
      provider: `Twilio (${new Date().toISOString()})`
    }
    await admin.firestore().doc('appInfo/appInfo').update({ connectionConfig })
    functions.logger.log('Updated connection config', { connectionConfig })
  })

export const pairing = functions.https.onRequest(async (req, res) => {
  try {
    let result = await pairingFunction(req.body)
    res.send(result)
  } catch(error) {
    functions.logger.error(error)
    res.status(error?.statusCode || 500).send({
       error: error?.type || error?.message || 'unknown',
    })
  }
});

async function pairingFunction(body) {
  let { localCode, remoteCode, deviceKey, deviceName, devicePlatform, meta } = body

  if (meta?.deviceName) deviceName = meta.deviceName
  if (meta?.devicePlatform) devicePlatform = meta.devicePlatform

  functions.logger.log('Pairing started', { body })

  if (!localCode || !remoteCode || !deviceKey) {
    throw new ServerError('invalidParams', 400);
  }

  const localConnection = {
    date: new Date(),
    deviceName,
    localCode,
    remoteCode,
    deviceKey,
    devicePlatform: devicePlatform || null,
    meta: meta || {},
  }
  await admin.firestore().collection('connections').add(localConnection)
  functions.logger.log('Added local connection', localConnection)

  const remoteConnection = await new Promise((resolve, reject) => {
    let unsubscribe;
    const timerId = setTimeout(() => {
      unsubscribe()
      reject(new ServerError('timeout', 400, 'Pairing timed out. Verify you entered the correct pairing codes on both devices.'))
    }, 60 * 1000)

    async function handleConnectionSnapshot(snapshot) {
      for (const change of snapshot.docChanges()) {
        if (change.type === 'added') {
          const data = change.doc.data()
          functions.logger.log('New pair candidate', data)
          await change.doc.ref.delete()
          if (data.localCode === remoteCode) {
            clearInterval(timerId)
            unsubscribe()
            resolve(data)
          } else {
            functions.logger.error('Invalid pairing code found')
          }
        }
      }
    }
    
    unsubscribe = admin.firestore()
      .collection('connections')
      .where('remoteCode', '==', localCode)
      .onSnapshot(async snapshot => {
        try {
          await handleConnectionSnapshot(snapshot)
        } catch(error) {
          functions.logger.log('Could not handle pairing connections', error)
          reject(error)
        }
      }, (error) => {
        functions.logger.log('Could not listen for pairing connections', error)
        reject(error)
      })
  });

  const response = {
    deviceKey: remoteConnection.deviceKey,
    deviceName: remoteConnection.deviceName, // Deprecated
    devicePlatform: remoteConnection.devicePlatform, // Deprecated
    meta: remoteConnection.meta || {},
  }

  functions.logger.log('Pairing succeeded', response)

  return response
}
