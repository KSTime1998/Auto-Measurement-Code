function [tripped, reason] = handle_fault()
    % ARC / INTERLOCK 감지만 수행하고 원인을 반환
    tripped = false;
    reason  = "";

    if getappdata(0, 'ARC_DETECTED')
        tripped = true;
        reason  = "ARC";
        return;
    end
% 컨버테크에서는 사용안함. 스펠만장비에서 start_arc_timer_shrared.m 파일에서 사용
    % if getappdata(0, 'INTERLOCK_FAULT')
    %     tripped = true;
    %     reason  = "INTERLOCK";
    %     return;
    % end
end
