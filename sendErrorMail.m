function sendErrorMail(fromAddress, password, toAddress, subject, message)
    % ===================================================
    %  메일 서버 설정 (네이버 SMTP, SSL 사용)
    % ===================================================
    setpref('Internet','E_mail',fromAddress);
    setpref('Internet','SMTP_Server','smtp.naver.com');
    setpref('Internet','SMTP_Username',fromAddress);
    setpref('Internet','SMTP_Password',password);

    props = java.lang.System.getProperties;
    props.setProperty('mail.smtp.auth','true');
    props.setProperty('mail.smtp.port','465');
    props.setProperty('mail.smtp.socketFactory.port','465');
    props.setProperty('mail.smtp.socketFactory.class','javax.net.ssl.SSLSocketFactory');
    props.setProperty('mail.smtp.socketFactory.fallback','false');

    % ===================================================
    %  메일 발송
    % ===================================================
    try
        % ✅ 여기서 toAddress는 string 또는 cell array of string 허용
        % ✅ subject, message는 반드시 문자열(string)이어야 함
        sendmail(toAddress, subject, message);
        fprintf('📧 오류 알림 메일 발송 완료 → %s\n', strjoin(cellstr(toAddress), ', '));
    catch ME
        fprintf('!!! 메일 발송 실패: %s\n', ME.message);
    end
end
