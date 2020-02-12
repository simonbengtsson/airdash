if (require('electron-is-dev')) {
  document.querySelector('#app-name').textContent = 'AirDash Dev'
}

document.querySelector('#location').value = locationFolder()
document.querySelector('#connection-id').textContent = getConnectionId()

document.querySelector('#select-location').onclick = async () => {
  const { dialog } = require('electron').remote
  const result = await dialog.showOpenDialog({
    properties: ['openDirectory'],
  })
  const location = result.filePaths[0]
  if (location) {
    localStorage.setItem('location', location)
    document.querySelector('#location').value = location
  }
}

let previousPeer = null
reconnect()
if (!getConnectionId()) {
  refreshDeviceId()
}

function refreshDeviceId() {
  const num = () => Math.floor(Math.random() * 900) + 100
  const newId = `${num()}-${num()}-${num()}`
  localStorage.setItem('connection-id', newId)
  document.querySelector('#connection-id').textContent = newId
  reconnect()
}

function reconnect() {
  if (previousPeer) previousPeer.destroy()
  const connectionId = `flownio-airdash-${getConnectionId()}`
  const peer = new peerjs.Peer(connectionId)
  console.log(`Listening on ${connectionId}...`)
  peer.on('connection', (conn) => {
    conn.on('data', (file) => {
      const path = require('path')
      const fs = require('fs')

      const filename = conn.metadata.filename || 'unknown'
      const filepath = path.join(locationFolder(), filename)
      fs.writeFileSync(filepath, new Buffer(file))
      conn.send('done')
      console.log('Received ' + filepath)

      notifyFileSaved(filename, filepath)
    })
  })
  previousPeer = peer
}


function notifyFileSaved(filename, filepath) {
  const title = `New File from:  ${getConnectionId()}`
  const image = `${__dirname}/trayIconTemplate@2x.png`
  const notifOptions = {
    body: `A new file has been saved, ${filename}`,
    icon: isImage(filename) ? filepath : image,
    silent: true,
  }

  const myNotification = new Notification(title, notifOptions)
  myNotification.onclick = () => {
    // we can do something when user click file,
    // for example open the directory, or preview the file
  }
}

function isImage(filename) {
  return /jpg|png|jpeg|svg|gif|/.test(filename)
}

function locationFolder() {
  const path = require('path')
  const os = require('os')
  const desktopPath = path.join(os.homedir(), 'Desktop')
  return localStorage.getItem('location') || desktopPath
}

function getConnectionId() {
  return localStorage.getItem('connection-id') || ''
}