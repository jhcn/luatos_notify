local cellular = {

	-- snr
	snr = function()
		return mobile.snr()
	end,

	-- csq
	csq = function()
		return mobile.csq()
	end,

	-- rsrp
	rsrp = function()
		return mobile.rsrp()
	end,

	-- rsrp
	rsrq = function()
		return mobile.rsrp()
	end,

	-- rssi
	rssi = function()
		return mobile.rssi()
	end,

	-- apn
	apn = function()
		return mobile.apn()
	end

}

return cellular