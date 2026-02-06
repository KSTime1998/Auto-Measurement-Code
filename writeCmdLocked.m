function writeCmdLocked(s, cmd, args)
% writeCmdLocked  — Spellman TX를 직렬화(락)해서 안전하게 전송
%   s   : serialport 객체
%   cmd : 숫자 명령 (예: 10, 22, 99 ...)
%   args: 문자열 인자 (예: "0", "1", "1234" ...)

    % 누가 쓰는 중이면 잠깐 양보 (1ms)
    while getappdata(0,'SERIAL_BUSY')
        if toc(t0) > waitLimit
            % 더 이상 기다리지 말고 에러로 튕김
            error('SERIAL:BUSY_TIMEOUT', ...
                'writeCmdLocked(%d): SERIAL_BUSY stuck for > %.3f s', ...
                cmd, toc(t0));
        end
        pause(0.001);
    end
    setappdata(0,'SERIAL_BUSY', true);
    c = onCleanup(@() setappdata(0,'SERIAL_BUSY', false));  %#ok<NASGU>

    % 실제 전송
    % try
    %     localWriteWithChecksum(s, cmd, args);
    % catch ME
    %     % 예외 나도 onCleanup으로 락 자동 해제됨
    %     warning('writeCmdLocked(%d) failed: %s', cmd, ME.message);
    %     return;
    % end
    localWriteWithChecksum(s, cmd, args);
    % 인터커맨드 간격(장비 안정용, 필요시 조절)
    pause(0.01);

    % (선택) 마지막 전송 시각 기록
    if isappdata(0,'RUN_T0')
        setappdata(0,'LAST_TX_T', toc(getappdata(0,'RUN_T0')));
    end
end
