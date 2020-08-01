
import { STATUSES } from './statuses.js'

export class Device {
    static STATUS_CONNECTING = 'connecting'
    static STATUS_READY = 'ready'
    static STATUS_ERROR = 'error'

    constructor(id, name, addedAt = new Date(), status = Device.STATUS_CONNECTING) {
        this.id = id
        this.name = name || id
        this.addedAt = addedAt
        this.status = status
    }

    persist() {
        localStorage.setItem(`DEVICE_${this.id}`, JSON.stringify(this))
    }

    getStatus() {
        return STATUSES[this.status] || STATUSES.error;
    }

    getStatusMessage() {
        return this.getStatus().message
    }

    getStatusColor() {
        return this.getStatus().color
    }

    setStatus(status) {
        console.log('Device.setStatus', status);
        this.status = status
        this.persist()
    }

    setConnecting() {
        this.setStatus(Device.STATUS_CONNECTING)
        return this
    }

    setReady() {
        this.setStatus(Device.STATUS_READY)
        return this
    }

    setError() {
        this.setStatus(Device.STATUS_ERROR)
        return this
    }
}
