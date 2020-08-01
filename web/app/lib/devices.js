import { Device } from './device.js'
import { setStatus } from './render.js'
import { tryConnection } from './connection.js'

export async function tryAddingDevice(id, element) {
    console.log(id)
    element.disabled = true
    setStatus('Connecting...')
    try {
        const result = await tryConnection(id)
        let newDevice = addDevice(id, result.deviceName || id)
        newDevice.setReady()
        setActiveDevice(id)
        return true
    } catch (error) {
        console.log(error)
        setStatus(error)
        element.disabled = false
        element.focus()
    }
}

export function deleteDevice(id) {
    localStorage.removeItem(`DEVICE_${id}`)
}

export function getDevices() {
    let devices =
        Object.entries(localStorage)
            .filter(([key, value]) => key.startsWith('DEVICE_'))
            .map(([key, device]) => JSON.parse(device))

    const mappedDevices = {}
    Object.keys(devices).forEach(id => {
        const device = devices[id]
        mappedDevices[device.id] = new Device(device.id, device.name, device.addedAt, device.status)
    })

    return mappedDevices
}

export function addDevice(code, name) {
    const newDevice = new Device(code, name)
    localStorage.setItem('DEVICE_' + code, JSON.stringify(newDevice))
    return newDevice;
}

export function setActiveDevice(code) {
    localStorage.setItem('connection-id', code)
}

export function getActiveDevice() {
    return localStorage.getItem('connection-id') || ''
}
