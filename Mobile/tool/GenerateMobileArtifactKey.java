import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Base64;

public final class GenerateMobileArtifactKey {
    private static final byte[] ED25519_PUBLIC_KEY_PREFIX = hex("302a300506032b6570032100");
    private static final byte[] ED25519_PRIVATE_KEY_SEED_PREFIX = hex("302e020100300506032b657004220420");

    public static void main(String[] args) throws Exception {
        var keyId = option(args, "--key-id", defaultKeyId());
        var output = Path.of(option(args, "--output", "secrets/artifact-signing"));
        Files.createDirectories(output);

        var generator = KeyPairGenerator.getInstance("Ed25519");
        KeyPair keyPair = generator.generateKeyPair();
        byte[] publicKey = rawPublicKey(keyPair.getPublic().getEncoded());
        byte[] privateSeed = rawPrivateSeed(keyPair.getPrivate().getEncoded());

        var publicKeyBase64 = Base64.getEncoder().encodeToString(publicKey);
        var privateSeedBase64 = Base64.getEncoder().encodeToString(privateSeed);
        var privatePkcs8Base64 = Base64.getEncoder().encodeToString(keyPair.getPrivate().getEncoded());
        var privatePem = pem("PRIVATE KEY", keyPair.getPrivate().getEncoded());
        var publicLine = keyId + ":" + publicKeyBase64;

        Files.writeString(output.resolve(keyId + ".public.txt"), publicLine + System.lineSeparator(), StandardCharsets.UTF_8);
        Files.writeString(output.resolve(keyId + ".private.pem"), privatePem, StandardCharsets.UTF_8);
        Files.writeString(
            output.resolve(keyId + ".private.json"),
            """
            {
              "keyId": "%s",
              "algorithm": "ed25519",
              "publicKeyBase64": "%s",
              "privateKeySeedBase64": "%s",
              "privateKeyPkcs8Base64": "%s",
              "publicKeyLine": "%s",
              "createdAtUtc": "%s",
              "usage": "mobile artifact signature"
            }
            """.formatted(
                escape(keyId),
                publicKeyBase64,
                privateSeedBase64,
                privatePkcs8Base64,
                escape(publicLine),
                Instant.now().toString()
            ),
            StandardCharsets.UTF_8
        );

        System.out.println("keyId=" + keyId);
        System.out.println("publicKeyLine=" + publicLine);
        System.out.println("privateJson=" + output.resolve(keyId + ".private.json"));
        System.out.println("privatePem=" + output.resolve(keyId + ".private.pem"));
        System.out.println("publicTxt=" + output.resolve(keyId + ".public.txt"));
    }

    private static String defaultKeyId() {
        return "mobile-release-" + LocalDate.now(ZoneOffset.UTC).format(DateTimeFormatter.BASIC_ISO_DATE) + "-01";
    }

    private static String option(String[] args, String name, String fallback) {
        for (int i = 0; i + 1 < args.length; i++) {
            if (name.equals(args[i])) {
                return args[i + 1];
            }
        }
        return fallback;
    }

    private static byte[] rawPublicKey(byte[] encoded) throws GeneralSecurityException {
        if (!startsWith(encoded, ED25519_PUBLIC_KEY_PREFIX)) {
            throw new GeneralSecurityException("Unexpected Ed25519 public key encoding.");
        }
        return slice(encoded, ED25519_PUBLIC_KEY_PREFIX.length, 32);
    }

    private static byte[] rawPrivateSeed(byte[] encoded) throws GeneralSecurityException {
        if (!startsWith(encoded, ED25519_PRIVATE_KEY_SEED_PREFIX)) {
            throw new GeneralSecurityException("Unexpected Ed25519 private key encoding.");
        }
        return slice(encoded, ED25519_PRIVATE_KEY_SEED_PREFIX.length, 32);
    }

    private static boolean startsWith(byte[] value, byte[] prefix) {
        if (value.length < prefix.length) {
            return false;
        }
        for (int i = 0; i < prefix.length; i++) {
            if (value[i] != prefix[i]) {
                return false;
            }
        }
        return true;
    }

    private static byte[] slice(byte[] value, int offset, int length) {
        var result = new byte[length];
        System.arraycopy(value, offset, result, 0, length);
        return result;
    }

    private static String pem(String label, byte[] value) {
        var encoded = Base64.getMimeEncoder(64, System.lineSeparator().getBytes(StandardCharsets.UTF_8)).encodeToString(value);
        return "-----BEGIN " + label + "-----" + System.lineSeparator()
            + encoded + System.lineSeparator()
            + "-----END " + label + "-----" + System.lineSeparator();
    }

    private static byte[] hex(String value) {
        var result = new byte[value.length() / 2];
        for (int i = 0; i < result.length; i++) {
            result[i] = (byte) Integer.parseInt(value.substring(i * 2, i * 2 + 2), 16);
        }
        return result;
    }

    private static String escape(String value) throws IOException {
        return value.replace("\\", "\\\\").replace("\"", "\\\"");
    }
}
