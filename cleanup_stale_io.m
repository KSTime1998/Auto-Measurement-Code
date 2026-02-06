function cleanup_stale_io()
    fprintf('[cleanup] stopping timers and releasing IO...\n');

    % 1) 타이머(ARC 폴링 등) 정지/삭제
    try
        t = timerfindall;
        if ~isempty(t)
            try, stop(t);   catch, end
            try, delete(t); catch, end
        end
    catch, end

    % 2) serialport: 콜백 OFF → 버퍼 flush → 삭제
    try
        sp = serialportfind;  % R2020b+
    catch
        sp = [];
    end
    for k = 1:numel(sp)
        try, configureCallback(sp(k),"off"); catch, end
        try, flush(sp(k));                 catch, end
        try, delete(sp(k));                catch, end
    end

    % 3) VISA/GPIB 등 legacy 객체: fclose → delete
    try
        objs = instrfind;   % legacy visa/gpib/tcpip 등
        if ~isempty(objs)
            try, fclose(objs); catch, end
            try, delete(objs); catch, end
        end
    catch, end

    % 4) 워크스페이스 참조 제거 (base와 현 workspace 둘 다)
    try, evalin('base','clear s ardu ps_obj multi_obj fun_obj'); catch, end
    try, clear s ardu ps_obj multi_obj fun_obj;                   catch, end

    % 5) (선택) 잠깐 대기: OS 핸들 해제 안정화
    pause(0.1);

    fprintf('[cleanup] done.\n');
end
