function ok = wait_ack(ps_obj, cmdChar, timeout)
    if nargin < 3, timeout = 0.3; end % 입력 인수가 3개 미만이면 timeout을 0.3으로 함
    ok = false;
    t0 = tic;

    % timeout 될 때까지 ps_obj.NumBytesAvailable이 1이 되지 않으면 에러를 띄움
    while ps_obj.NumBytesAvailable < 1
        if toc(t0) > timeout
            error('%s ACK timeout (%.3fs)', cmdChar, timeout);
        end
        pause(0.005);
    end

    % ack를 읽었을 때 0x06이 아니면 에러를 띄움
    ack = read(ps_obj, 1, "uint8");
    if ack ~= 0x06
        error('%s ACK invalid: 0x%02X', cmdChar, ack);
    end

    ok = true;
end
