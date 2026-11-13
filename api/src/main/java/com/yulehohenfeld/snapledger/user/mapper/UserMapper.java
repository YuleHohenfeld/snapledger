package com.yulehohenfeld.snapledger.user.mapper;

import org.mapstruct.Mapper;

import com.yulehohenfeld.snapledger.user.dto.UserResponse;
import com.yulehohenfeld.snapledger.user.entity.User;

/** User to UserResponse only; never the opposite direction. PT: Só User para UserResponse; nunca o contrário.
 *  Notes: docs/code-notes/user.md#usermapper */
@Mapper(componentModel = "spring")
public interface UserMapper {

    UserResponse toResponse(User user);
}
