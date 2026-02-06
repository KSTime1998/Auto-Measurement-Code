function acquire_lock()
while getappdata(0,'SERIAL_BUSY')
    pause(0.001);
end
setappdata(0,'SERIAL_BUSY',true);
end

