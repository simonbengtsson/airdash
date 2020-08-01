import { tryConnection, sendPayload } from './lib/connection.js'
import { parseFormData } from './lib/bodyParser.js'
import {
  tryAddingDevice,
  getDevices,
  setActiveDevice,
  getActiveDevice,
  deleteDevice,
} from './lib/devices.js'

import {
  setStatus,
  renderAddDevice,
  renderDeviceRow,
} from './lib/render.js'

console.log('Loading app.js')

let showAddButton = true;

; (async function () {
  try {
    await navigator.serviceWorker.register('./sw.js')
    navigator.serviceWorker.addEventListener('message', swMessageReceived);
  } catch (err) {
    console.log('sw failed', err)
  }

  render()
  await connectToDevices()
})()

async function connectToDevices() {
  const devices = getDevices()
  for (const device of Object.values(devices)) {
    device.setConnecting();

    render()

    tryConnection(device.id)
      .then(() => device.setReady())
      .catch(() => device.setError())
      .then(() => render())
  }
}

async function swMessageReceived(event) {
  console.log('Message received')
  let { body, headers } = event.data
  const request = new Request('', { method: 'POST', body, headers })

  try {
    const { payload, meta } = await parseFormData(request)
    const activeDevice = getActiveDevice() || ''
    await sendPayload(payload, meta, activeDevice, setStatus)
  } catch (error) {
    console.error(error)
    setStatus(error)
  }
}

function render() {
  let activeDevice = getActiveDevice()
  const devices = getDevices()

  if (!devices[activeDevice]) {
    activeDevice = Object.keys(devices)[0]
  }

  const deviceRows = Object
    .entries(devices)
    .map(([id, device]) => renderDeviceRow(id, device, id === activeDevice))
    .join('')

  const content = `
    <section>
        <form>${deviceRows}</form>
        <div style="clear:both;"></div>
        <div style="margin: 10px 0;">${renderAddDevice(showAddButton)}</div>
    </section>
    <section style="margin-bottom: 40px">
        <p id="message" style="min-height: 20px;"></p>
        <form id="file-form" action="./" method="POST" enctype="multipart/form-data">
            <input name="rawtext" type="hidden" value="">
            <label for="file-input" id="file-button">Select file to send</label>
            <!-- bodyParser.js requires that the file input is the last element -->
            <input id="file-input" name="file" type="file" style="opacity: 0; position: absolute; z-index: -1">
        </form>
        <p style="color: #aaa; text-align: center; margin-top: 50px;">v0.2.0</p>
    </section>
  `
  document.querySelector('#content').innerHTML = content
  attachDocument()
}

function attachDocument() {
  if (!showAddButton) {
    new Cleave('#code-input', {
      delimiter: '-',
      blocks: [3, 3, 3],
      numericOnly: true
    });
  }

  document
    .querySelector('#file-input')
    .addEventListener('change', (e) => {
      const element = e.currentTarget
      // We could send the file directly here, but submitting it with the form
      // makes it easier to debug the service worker used for handling files from
      // the Android share menu
      console.log('File picked', element.files[0].name)
      gtag('filePicked', 'event');
      document.querySelector('#file-form').submit()
      setStatus('Preparing...')
    })

  const codeInputElement = () => document.querySelector('#code-input')
  if (codeInputElement()) {
    codeInputElement()
      .addEventListener('focusout', (e) => {
        if (!e.currentTarget.disabled) {
          showAddButton = true
          render()
        }
      })

    codeInputElement()
      .addEventListener('input', async (e) => {
        const element = e.currentTarget
        if (element.value.length === 11) {
          tryAddingDevice(element.value, element, showAddButton)
            .then(() => showAddButton = true)
            .then(() => render())
        }
      })
  }

  const addDeviceButton = document.querySelector('#add-device-btn')
  if (addDeviceButton) {
    addDeviceButton
      .addEventListener('click', () => {
        showAddButton = false
        render()
        codeInputElement().focus()
      })
  }

  document
    .querySelectorAll('.remove-device-btn')
    .forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation()

        const deviceId = e.currentTarget.dataset.deviceId
        deleteDevice(deviceId)
        render()
      })
    })

  document.querySelectorAll('.device')
    .forEach((btn) => {
      btn.addEventListener('click', (e) => {
        const element = e.currentTarget
        element.querySelector('input').checked = true
        setActiveDevice(element.value)
      })
    })

  let deferredPrompt;
  document.querySelector('#android-install')
    .addEventListener('click', () => {
      deferredPrompt.prompt()
    })
  window
    .addEventListener('beforeinstallprompt', (e) => {
      deferredPrompt = e
    });
}
