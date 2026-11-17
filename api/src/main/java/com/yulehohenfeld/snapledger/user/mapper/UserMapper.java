package com.yulehohenfeld.snapledger.user.mapper;

import org.mapstruct.Mapper;
import org.mapstruct.Mapping;

import com.yulehohenfeld.snapledger.user.dto.UserResponse;
import com.yulehohenfeld.snapledger.user.entity.User;

/** User to UserResponse only; never the opposite direction. PT: Só User para UserResponse; nunca o contrário.
 *  Notes: docs/code-notes/user.md#usermapper */
@Mapper(componentModel = "spring")
public interface UserMapper {

    // The response says only whether the email is verified, never when.
    // PT: A resposta diz só se o email está verificado, nunca quando.
    @Mapping(target = "emailVerified", expression = "java(user.getEmailVerifiedAt() != null)")
    UserResponse toResponse(User user);
}
