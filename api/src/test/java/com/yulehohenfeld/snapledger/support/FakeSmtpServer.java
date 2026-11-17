package com.yulehohenfeld.snapledger.support;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.nio.charset.StandardCharsets;

/**
 * A minimal in-process SMTP server that accepts every message and keeps nothing, so tests can
 * drive the real mail library without Docker or Mailpit.
 *
 * <p>PT: Um servidor SMTP mínimo, dentro do processo, que aceita toda mensagem e não guarda nada,
 * para os testes usarem a biblioteca de email de verdade sem Docker nem Mailpit.
 */
public final class FakeSmtpServer implements AutoCloseable {

    private final ServerSocket server;

    public FakeSmtpServer() throws IOException {
        server = new ServerSocket(0, 5, InetAddress.getLoopbackAddress());
        var thread = new Thread(this::serve, "fake-smtp");
        thread.setDaemon(true);
        thread.start();
    }

    public int port() {
        return server.getLocalPort();
    }

    private void serve() {
        while (!server.isClosed()) {
            try (var socket = server.accept();
                 var in = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
                 var out = new PrintWriter(socket.getOutputStream(), true, StandardCharsets.UTF_8)) {
                out.print("220 fake ESMTP\r\n");
                out.flush();
                String line;
                boolean data = false;
                while ((line = in.readLine()) != null) {
                    if (data) {
                        if (line.equals(".")) {
                            data = false;
                            reply(out, "250 queued");
                        }
                    } else if (line.regionMatches(true, 0, "EHLO", 0, 4)) {
                        reply(out, "250 fake");
                    } else if (line.regionMatches(true, 0, "DATA", 0, 4)) {
                        data = true;
                        reply(out, "354 go ahead");
                    } else if (line.regionMatches(true, 0, "QUIT", 0, 4)) {
                        reply(out, "221 bye");
                        break;
                    } else {
                        reply(out, "250 ok");
                    }
                }
            } catch (IOException e) {
                // Closed by close() or by the client; nothing to report in a test helper.
                // PT: Fechado pelo close() ou pelo cliente; nada a reportar num helper de teste.
            }
        }
    }

    private static void reply(PrintWriter out, String line) {
        out.print(line + "\r\n");
        out.flush();
    }

    @Override
    public void close() throws IOException {
        server.close();
    }
}
